require 'socket'
require 'uri'

server = TCPServer.new(4567)
puts "Listening on port 4567..."

loop do
  client = server.accept

  # Read request line
  request_line = client.gets
  method, full_path, _ = request_line.split(' ', 3) if request_line

  # Parse path and query string
  path = full_path ? full_path.split('?').first : ""
  query_string = full_path && full_path.include?('?') ? full_path.split('?', 2)[1] : ""

  # Decode query string if present
  decoded_query = query_string && !query_string.empty? ? URI.decode_www_form(query_string).to_h : {}

  # Read headers
  headers = {}
  while (line = client.gets)
    line = line.strip
    break if line.empty?
    key, value = line.split(': ', 2)
    headers[key] = value if key && value
  end

  # Read body if present, decode if form data
  body = ""
  decoded_body = {}
  if headers["Content-Length"]
    body = client.read(headers["Content-Length"].to_i)
    if headers["Content-Type"] && headers["Content-Type"].include?("application/x-www-form-urlencoded")
      decoded_body = URI.decode_www_form(body).to_h
    end
  end

  # Build response sections
  response_body = []
  response_body << '-----------------------------------------'
  response_body << 'This is what you sent:'
  response_body << '-----------------------------------------'
  response_body << "Method: #{ method }"
  response_body << "Path: #{ path }"
  response_body << ''
  unless decoded_query.empty?
    response_body << 'Query string:'
    # response_body << decoded_query
    response_body << decoded_query.map { |k, v| "  #{k}=#{v}" }.join("\n")
    response_body << ''
  end

  unless decoded_body.empty?
    response_body << 'POST Body:'
    # response_body << decoded_body
    response_body << decoded_body.map { |k, v| "  #{k}=#{v}" }.join("\n")
    response_body << ''
  end

  response_body << 'HTTP Headers:'
  response_body << headers.map { |k, v| "  #{k}: #{v}" }.join("\n")
  response_body_txt = response_body.join("\n")

  response = "HTTP/1.1 200 OK\r\n" \
             "Content-Type: text/plain\r\n" \
             "Connection: close\r\n" \
             "Content-Length: #{response_body_txt.bytesize}\r\n" \
             "\r\n" \
             "#{response_body_txt}"

  client.write(response)
  client.close
end
