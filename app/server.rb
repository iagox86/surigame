require 'base64'
require 'json'
require 'pathname'
require 'set'
require 'sinatra'
require 'singlogger'
require 'socket'
require 'timeout'
require 'tempfile'

# Markdown
require 'redcarpet'

# Safe YAML parsing
require 'safe_yaml'
SafeYAML::OPTIONS[:default_mode] = :safe

require_relative('./fakecap')
require_relative('./suricata')

GAME_NAME = 'SuriGame'
GAME_LOGO = '/greynoise.jpg'

DEBUG = ENV['DEBUG'] == 'true'

# These are what get returned to the user by default
PUBLIC_FIELDS = %w[
  id
  name
  type
  divider_before
  text
  hints
  base_request
  next
  previous
  base_rule
  evil_requests
  innocent_requests
  rules
]

::SingLogger.set_level_from_string(level: ENV['log_level'] || 'debug')
LOGGER = ::SingLogger.instance()

# Ideally, we set all these in the Dockerfile
set :bind, ENV['HOST'] || '0.0.0.0'
set :port, ENV['PORT'] || '1234'
set :host_authorization, { permitted_hosts: [] }

# set :logging, Logger::DEBUG

PROFILE = ENV['PROFILE'] || 'dev'

SCRIPT = File.expand_path(__FILE__)

SURICATA = ENV['suricata'] || `which suricata`.strip
unless File.executable?(SURICATA)
  raise "Couldn't find Suricata executable (set with SURICATA=...): #{ SURICATA }"
end

TARGETS = ::YAML.load_file(File.join(__dir__, 'targets.yaml')).map do |key, target|
  [key, target[PROFILE]]
end.to_h

# Load the levels from the levels/ directory
LEVEL_IDS = ::Set.new()
LEVELS = ::Dir.glob(::File.join(__dir__, 'levels', '**', '*.yaml')).sort.map do |config|
  LOGGER.info "Loading #{ config }..."
  # Add the id (based on the filename) to each config file
  pathname = ::Pathname.new(config)
  id = "#{ pathname.dirname.basename }--#{ pathname.basename('.yaml') }"

  unless LEVEL_IDS.add?(id)
    raise "Duplicate ID: #{ id }"
  end

  { 'id' => id, 'filename' => config }.merge(::YAML.load_file(config))
end.map do |level|
  # Give the Suricata rules a consistent ID
  level['rules'] = level['rules']&.each_with_index&.map do |rule, i|
    rule =~ /sid:\s*([0-9]*)/
    id = Regexp.last_match(1).to_s

    {
      'rule' => rule.gsub('%%ID%%', id),
      'id' => id,
    }
  end

  level['evil_requests'] = level['evil_requests']&.each_with_index&.map do |request, i|
    {
      'request' => request,
      'id' => "#{ level['id'] }-evil-#{ i + 1 }"
    }
  end

  level['innocent_requests'] = level['innocent_requests']&.each_with_index&.map do |request, i|
    {
      'request' => request,
      'id' => "#{ level['id'] }-innocent-#{ i + 1 }"
    }
  end

  level['target'] = TARGETS[level['target']]

  if level['type'] == 'exploit' && level['target'].nil?
    raise "Level is missing a target: #{ level }"
  end

  level
end

def does_request_match(request, rules)
  # Don't bother with empty rulesets
  if rules == []
    return {}
  end

  rules.each do |rule|
    unless rule.is_a?(String)
      pp rules
      raise "Rules isn't an array of strings!"
    end
  end

  Tempfile.create('request.pcap') do |pcap_file|
    pcap_file.write(FakeCap.fake_http(request))
    pcap_file.close
    return run_suricata(pcap_file.to_path, rules, suricata: SURICATA)
  end
end

def format_http(http)
  headers, body = http.split(/\r?\n\r?\n/, 2)

  # Host: is also mandatory
  unless headers =~ /^Host:/i
    headers.concat("\r\nHost: localhost")
  end

  # Make sure they don't mess up content-length
  if headers.start_with?('POST')
    if headers =~ /^Content-Length:/i
      headers = headers.gsub(/^Content-Length.*/i, "Content-Length: #{ (body || '').length }")
    else
      headers.concat("\r\nContent-Length: #{ (body || '').length }")
    end

    if headers !~ /^Content-Type:/i
      headers.concat("\r\nContent-Type: application/x-www-form-urlencoded")
    end
  end

  return [headers, body || ''].join("\r\n\r\n")
end

def try_exploit(level, request, quiet: false)
  s = nil
  ::Timeout.timeout(10) do
    unless quiet
      LOGGER.info("Connecting to #{ level['target']['host'] }:#{ level['target']['port'] }")
    end
    s = TCPSocket.new(level['target']['host'], level['target']['port'])

    unless quiet
      LOGGER.info("Sending the request to #{ level['target']['host'] }:#{ level['target']['port'] }: #{ request.length } bytes")
      LOGGER.debug("Request:\n#{ request }")
    end
    s.write(request)

    unless quiet
      LOGGER.info('Reading the response')
    end
    response = s.readpartial(8192)

    unless quiet
      LOGGER.debug("Response:\n#{ response&.split(/\r?\n\r?\n/)&.dig(0) }\n[...]")
    end

    return (response =~ ::Regexp.new(level['expected_output'])) ? true : false
  end
end

def self_test()
  LOGGER.info 'Testing rules...'
  LEVELS.each do |level|
    puts "Testing #{ level['id'] }..."

    # Ensure that rules a) have no errors, and b) match the base request
    if level['rules'] && level['rules'].length > 0
      # Run the Suricata rules against the base request
      result = does_request_match(format_http(level['base_request']), level['rules'].map { |rule| rule['rule'] })

      # Errors?
      if result[:errors] && result[:errors].length > 0
        LOGGER.fatal "Error in rule from #{ level['filename'] }:"

        result[:errors].each do |error|
          puts "* #{ error }"
        end
        exit
      end

      # Does it match?
      unless result[:results] && result[:results].length > 0
        LOGGER.fatal "Rules don't match base request @ #{ level['filename'] }:"
        puts level['rules'].map { |rule| rule['rule'] }.join("\n")
        puts level['base_request']
        exit
      end

      # Make sure the base exploit works
      unless try_exploit(level, format_http(level['base_request']), quiet: true)
        LOGGER.fatal "Base exploit doesn't work @ #{ level['filename'] }:"
        exit
      end
    end

    # Test solutions
    if level['type'] == 'exploit' || level['type'] == 'suricata'
      if level['solution'].nil?
        LOGGER.fatal "No solution for #{ level['id'] }"
        exit
      end

      if level['type'] == 'exploit'
        caught = does_request_match(level['solution'], level['rules']&.map { |rule| rule['rule'] } || [])[:results]

        unless caught.nil? || caught.empty?
          LOGGER.fatal "Solution is caught by a rule @ #{ level['filename'] }"
          puts 'Rules:'
          pp level['rules']
          puts
          puts 'Solution:'
          pp level['solution']
          exit
        end

        unless try_exploit(level, format_http(level['solution']), quiet: true)
          LOGGER.fatal "Solution doesn't work @ #{ level['filename'] }"
          exit
        end
      end
    end
  end

  LOGGER.info 'Rules look good!'
end

# Sanity check our rules
if DEBUG
  self_test()
end

# Add the next/previous levels
0.upto(LEVELS.length - 2) do |i|
  LEVELS[i + 1]['previous'] = LEVELS[i]['id']
  LEVELS[i]['next'] = LEVELS[i + 1]['id']
end

LEVELS_BY_ID = LEVELS.map { |l| [l['id'], l] }.to_h

def unlocked_levels
  return LEVELS.map { |l| l.slice(*PUBLIC_FIELDS) }
end

def get_level(id)
  return LEVELS_BY_ID[id]&.slice(*PUBLIC_FIELDS)
end

MARKDOWN = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true, prettify: true, fenced_code_blocks: true)
def md(text)
  return MARKDOWN.render(text)
end

get '/' do
  erb(
    :index,
    locals: {
      levels: unlocked_levels,
      debug: DEBUG,
    }
  )
end

get '/level/:id' do
  level = get_level(@params[:id])

  if level
    erb(
      :"levels/#{ level['type'] }",
      locals: {
        levels: unlocked_levels,
        level: level,
        debug: DEBUG,
      }
    )
  else
    erb(
      :error,
      locals: {
        levels: unlocked_levels,
        error: 'No such level!',
        debug: DEBUG,
      }
    )
  end
end

# Define routes starting with /api
before do
  if request.nil? || request.content_type.nil?
    next
  end

  unless request.content_type.start_with?('application/json')
    next
  end

  begin
    request.body.rewind
    @body = ::JSON.parse(request.body.read)
  rescue ::JSON::ParserError => e
    # Handle JSON parsing errors
    LOGGER.error("JSON parsing error: #{ e.message }")

    halt(400, { error: 'JSON parsing error!' }.to_json)
  rescue StandardError => e
    # Handle any other unexpected errors
    LOGGER.error("Unexpected error: #{ e.message }")
    puts e.backtrace

    halt(500, { error: "Unexpected error: #{ e.message }" }.to_json)
  end
end

get '/api/levels/all' do
  if DEBUG
    return 200, LEVEL_IDS.to_a.to_json
  else
    return 200, [].to_json
  end
end

get '/api/levels/:id' do
  level = get_level(@params[:id])

  unless level
    return 400, { 'error' => 'No such level!' }.to_json
  end

  return 200, level.to_json
end

post '/api/exploit/:id' do
  if @body['request'].nil? || @body['request'].empty?
    return 400, { 'error' => 'Missing request!' }.to_json
  end

  level = LEVELS_BY_ID[@params[:id]]
  if level.nil?
    return 400, { 'error' => 'Invalid level!' }.to_json
  end

  # Clean up the request (newlines, etc)
  request = @body['request']
  unless @body['dont-fix']
    request = format_http(request)
  end

  # If there are Suricata rules, do that first
  matches = does_request_match(request, level['rules']&.map { |rule| rule['rule'] } || [])
  unless matches[:errors].nil? || matches[:errors].empty?
    LOGGER.error(matches[:errors])
    return 500, { 'error' => 'One of our Suricata rules caused an error! This is probably a game problem...' }.to_json
  end

  caught = does_request_match(request, level['rules']&.map { |rule| rule['rule'] } || [])[:results]&.map do |result|
    result.dig('alert', 'signature_id') || 'unknown-rule'
  end

  unless caught.nil? || caught.empty?
    return 200, {
      'fixed_request' => ::Base64.strict_encode64(request),
      'response' => ::Base64.strict_encode64("Caught by a Suricata rule! sid: #{ caught.join(', ') }"),
      'caught' => caught || [],
      'completed' => false,
    }.to_json
  end

  # Define the socket so we can ensure it's closed
  begin
    s = nil
    ::Timeout.timeout(10) do
      LOGGER.info("Connecting to #{ level['target']['host'] }:#{ level['target']['port'] }")
      s = TCPSocket.new(level['target']['host'], level['target']['port'])
      LOGGER.info("Sending the request to #{ level['target']['host'] }:#{ level['target']['port'] }: #{ request.length } bytes")
      LOGGER.debug("Request:\n#{ request }")
      s.write(request)
      LOGGER.info('Reading the response')
      response = s.readpartial(8192)

      LOGGER.debug("Response:\n#{ response&.split(/\r?\n\r?\n/)&.dig(0) }\n[...]")

      return 200, {
        'fixed_request' => ::Base64.strict_encode64(request),
        'response' => ::Base64.strict_encode64(response),
        'caught' => [],
        'completed' => !(response =~ ::Regexp.new(level['expected_output'])).nil?,
      }.to_json
    end
  rescue ::Timeout::Error
    LOGGER.warn('Timeout!')
    if @body['dont-fix']
      return 500, { 'error' => "Request to target server timed out! You might consider unchecking 'don't fix my HTTP request' (or fixing Connection/Host/Content-Length headers manually)..." }.to_json
    end

    return 500, { 'error' => 'Request to target server timed out! This is probably an infrastructure problem, or some header is causing the server to wait...' }.to_json
  rescue ::Errno::ECONNREFUSED => e
    LOGGER.error("Connection refused: #{ e }")
    return 500, { 'error' => 'Connection refused to target server! This is probably an infrastructure problem...' }.to_json
  rescue ::StandardError => e
    LOGGER.error("Error running exploit (#{ e.class }): #{ e }")
    puts e.backtrace
    return 500, { 'error' => "Error running exploit: #{ e }" }.to_json
  ensure
    s&.close
  end
end

post '/api/demo/:id' do
  level = LEVELS_BY_ID[@params[:id]]
  if level.nil?
    return 400, { 'error' => 'Invalid level!' }.to_json
  end

  if @body['rule'].nil? || @body['rule'].empty?
    return 400, { 'error' => 'Missing rule!' }.to_json
  end

  if @body['request'].nil? || @body['request'].empty?
    return 400, { 'error' => 'Missing rule!' }.to_json
  end

  result = does_request_match(@body['request'], @body['rule'].split(/\r?\n/))

  unless result[:errors].empty?
    return 200, {
      'completed' => false,
      'result' => 'error',
      'errors' => result[:errors],
    }.to_json
  end

  if level['should_match'].nil?
    level['should_match'] = true
  end

  if result[:results].empty?
    return 200, {
      'completed' => level['should_match'] == false,
      'result' => 'miss',
    }.to_json
  else
    return 200, {
      'completed' => level['should_match'] == true,
      'result' => 'match',
    }.to_json
  end
end

post '/api/suricata/:id' do
  if @body['rule'].nil? || @body['rule'].empty?
    return 400, { 'error' => 'Missing rule!' }.to_json
  end

  level = LEVELS_BY_ID[@params[:id]]
  if level.nil?
    return 400, { 'error' => 'Invalid level!' }.to_json
  end

  begin
    ::Timeout.timeout(10) do
      good = true
      results = []

      level['evil_requests'].each do |evil_request|
        # Check if the evil request matches
        evil_test = does_request_match(evil_request['request'], @body['rule'].split(/\r?\n/))

        # If there's an error in the Suricata rule, only add it to the output
        # once and then close things out
        unless evil_test[:errors].empty?
          results.concat(evil_test[:errors].map { |e| { 'type' => 'error', 'message' => "ERROR: #{ e }" } })
          return 200, {
            'completed' => false,
            'results' => results,
          }.to_json
        end

        # If the results are empty, it's a miss!
        if evil_test[:results].empty?
          results << { 'type' => 'miss', 'message' => 'BAD: Rule(s) missed an evil payload!', id: evil_request['id'] }
          good = false
        else
          results << { 'type' => 'success', 'message' => 'GOOD: Rule(s) matched an evil payload!', id: evil_request['id'] }
        end
      end

      # Check if any of the good tests match
      level['innocent_requests'].each do |innocent_request|
        # We ignore errors because they should be the same as earlier
        innocent_test = does_request_match(innocent_request['request'], @body['rule'].split(/\r?\n/))

        if innocent_test[:results].empty?
          results << { 'type' => 'success', 'message' => "GOOD: Rule(s) didn't match an innocent payload!", id: innocent_request['id'] }
        else
          results << { 'type' => 'overmatch', 'message' => 'BAD: Rule(s) matched an innocent payload!!', id: innocent_request['id'] }
        end
      end

      return 200, {
        'completed' => results.all? { |r| r['type'] == 'success' },
        'results' => results,
      }.to_json
    end
  rescue ::Timeout::Error
    LOGGER.warn('Timeout!')
    return 500, { 'error' => 'Rule timed out! Please report, unless you did this on purpose' }.to_json
  rescue ::StandardError => e
    LOGGER.error("Error testing rule (#{ e.class }): #{ e }")
    puts e.backtrace
    return 500, { 'error' => "Error testing rule: #{ e }" }.to_json
  end
end

get '/secret/self_test' do
  self_test()
end

get '/secret/summary' do
  out = []
  LEVELS.each do |level|
    if level['divider_before']
      out << "<h1>#{ level['divider_before'] }</h1>"
    end
    out << "<h2>#{ level['name'] }</h2>"
    out << "<a href=\"/level/#{ level['id'] }\">/level/#{ level['id'] }</a>"

    if level['solution_note']
      out << "Solution summary: #{ level['solution_note'] }"
    end

    if level['solution']
      out << "<pre>#{ CGI.escapeHTML(level['solution']) }</pre>"
    end
  end

  return 200, out.join("<br>\n")
end
