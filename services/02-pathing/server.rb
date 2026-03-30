# HEY Stop looking here! There be dragons! Hacker!!

require 'webrick'
require 'cgi'
require 'socket'

server = ::TCPServer.new('0.0.0.0', 80)

puts "Server ready: #{ server.inspect }"
loop do
  Thread.start(server.accept) do |client|
    puts "Accepted connection from #{ client.remote_address.getnameinfo.join(':') }"

    request_line = client.gets

    if request_line.nil?
      next
    end

    unless request_line.strip =~ /^[A-Z]+ ([^ ]+) ([^ ]+)$/i
      client.write "HTTP/400 Bad Request\r\n\r\n"
      next
    end

    verb = $0
    original_path = CGI.unescape($1)
    protocol = $2

    puts "Request line: #{ request_line }"

    path = "./#{ original_path[1..] }"

    puts "Path: #{ path }"

    result = 'HTTP/1.1 200 OK'
    content_type = "text/plain"
    if File.file?(path)
      data = File.read(path)

      if path.include?('.html')
        content_type = "text/html"
      end
    elsif File.directory?(path)
      if File.file?(File.join(path, 'index.txt'))
        data = File.read(File.join(path, 'index.txt'))
        content_type = "text/plain"
      else
        listing = Dir.entries(path)
        content_type = "text/plain"

        # Create the HTML header
        data = "Directory:\n"

        # Add each directory entry to the HTML table
        listing.each do |entry|
          #next if entry == '.' || entry == '..'

          data += "#{File.directory?(entry) ? 'DIR  ' : 'FILE '} #{entry}\n"
        end
      end
    else
      data = "Oops, that page wasn't found! Go back to <a href=\"/\">the starting page</a>?"
      result = 'HTTP/1.1 404 Not Found'
      content_type = 'text/html'
    end

    client.write([
      result,
      "Content-Type: #{ content_type }",
      "Last-Modified: #{ Time.now.httpdate }",
      "Date: #{ Time.now.httpdate }",
      'Connection: close',
      "Content-Length: #{ data.length }",
      '',
      data
    ].join("\r\n"))
  rescue ::StandardError => e
    puts "Oopsie: #{ e }"
    puts e.backtrace
  ensure
    client.close
  end
end
