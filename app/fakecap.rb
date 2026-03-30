require 'ipaddr'

class FakeCap
  FLAG_FIN = 0b00000001
  FLAG_SYN = 0b00000010
  FLAG_RST = 0b00000100
  FLAG_PSH = 0b00001000
  FLAG_ACK = 0b00010000
  FLAG_URG = 0b00100000

  def initialize(src_mac: '00:11:22:33:44:55', src_ip: '10.0.0.48', src_port: rand(1025..65_535), src_seq: rand(0..0xFFFFFFFF), dest_mac: 'aa:bb:cc:dd:ee:ff', dest_ip: '126.16.0.128', dest_port: 80, dest_seq: rand(0..0xFFFFFFFF), **_kwargs)
    @src = {
      mac: [src_mac.gsub(/:/, '')].pack('H12'),
      ip: IPAddr.new(src_ip).hton,
      port: src_port,
      seq: src_seq,
    }

    @dest = {
      mac: [dest_mac.gsub(/:/, '')].pack('H12'),
      ip: IPAddr.new(dest_ip).hton,
      port: dest_port,
      seq: dest_seq,
    }
  end

  def new_session!
    @src[:seq] = rand(0..0xFFFFFFFF)
    @dest[:seq] = rand(0..0xFFFFFFFF)
    @src[:port] = rand(0..0xFFFF)
  end

  def encode_global_header
    return [
      0xa1b2c3d4, # magic_number
      0x0002,     # version_major (2.4)
      0x0004,     # version_minor (2.4)
      0x00000000, # thistime (timezone offset from UTC in seconds)
      0x00000000, # sigfigs (accuracy of timestamps, always 0)
      0x0000FFFF, # snaplen
      0x00000001, # network (1 = ethernet)
    ].pack('NnnNNNN')
  end

  def encode_record(data)
    return [
      Time.now.to_i, # ts_set (timestamp in seconds since epoch)
      0x00000000, # ts_usec (nanoseconds or microseconds depending on the format?)
      data.length, # incl_len (number of octets of packet)
      data.length, # orig_len (actual length)
    ].pack('NNNN') + data
  end

  def encode_ethernet(inverted:)
    src  = inverted ? @dest : @src
    dest = inverted ? @src : @dest

    return [
      src[:mac], # dest mac
      dest[:mac], # source mac
      0x0800, # Type (0x0800 = IPv4)
    ].pack('a6a6n')
  end

  def encode_ip(tcp_length, inverted:)
    src  = inverted ? @dest : @src
    dest = inverted ? @src : @dest

    return [
      0b01000101, # 0100 = v4, 0101 = header length (20)
      0, # differentiated services field (?)
      20 + tcp_length, # total length (not counting the ethernet header)
      rand(0..65_535), # ipid
      0b0100000000000000, # 010 = don't fragment, 00.. = fragment id
      64, # TTL
      6, # Protocol (6 = TCP)
      rand(0..65_535), # header checksum
      src[:ip], # source addr
      dest[:ip], # dest addr
    ].pack('ccnnnccna4a4')
  end

  def encode_tcp(flags, payload, inverted:)
    src  = inverted ? @dest : @src
    dest = inverted ?  @src : @dest

    header_length = 20 / 4
    data = [
      src[:port], # source port
      dest[:port], # target port
      src[:seq], # sequence number
      dest[:seq], # ack number
      (header_length << 12) | flags, # header length (0101) + flags
      64_240, # window
      rand(0..65_535), # checksum
      0, # urg pointer
      payload, # Payload
    ].pack('nnNNnnnna*')

    # Increment seq by one for SYN/FIN packets
    if ((flags & FLAG_SYN) == FLAG_SYN) || ((flags & FLAG_FIN) == FLAG_FIN)
      src[:seq] += 1
    end

    # Update SEQ
    src[:seq] += payload.length

    return data
  end

  def encode_packet(flags, data, inverted:)
    tcp = encode_tcp(flags, data, inverted: inverted)
    ip = encode_ip(tcp.length, inverted: inverted)
    ethernet = encode_ethernet(inverted: inverted)

    return ethernet + ip + tcp
  end

  # Fake a request and an optional response
  def self.fake_binary(request, response = nil, count: 1, **kwargs)
    # Just pass through the various arguments
    fakecap = FakeCap.new(**kwargs)

    # Create a full TCP session
    session = fakecap.encode_global_header()

    count.times do
      session.concat(
        fakecap.encode_record(fakecap.encode_packet(FLAG_SYN,            '', inverted: false)) +
        fakecap.encode_record(fakecap.encode_packet(FLAG_SYN | FLAG_ACK, '', inverted: true)) +
        fakecap.encode_record(fakecap.encode_packet(FLAG_ACK,            '', inverted: false)) +
        fakecap.encode_record(fakecap.encode_packet(FLAG_ACK | FLAG_PSH, request, inverted: false)) +
        fakecap.encode_record(fakecap.encode_packet(FLAG_ACK,            '', inverted: true))
      )

      unless response.nil?
        session.concat(
          fakecap.encode_record(fakecap.encode_packet(FLAG_ACK | FLAG_PSH, response, inverted: true)),
          fakecap.encode_record(fakecap.encode_packet(FLAG_ACK,            '', inverted: false)),
        )
      end

      session.concat(
        fakecap.encode_record(fakecap.encode_packet(FLAG_FIN | FLAG_ACK, '', inverted: false)),
        fakecap.encode_record(fakecap.encode_packet(FLAG_FIN | FLAG_ACK, '', inverted: true)),
        fakecap.encode_record(fakecap.encode_packet(FLAG_ACK,            '', inverted: false)),
      )

      fakecap.new_session!()
    end

    return session
  end

  # Fake an HTTP request/response (by default, response is a very basic 404)
  def self.fake_http(request, response = nil, clean_up_http: true, **kwargs)
    if response.nil?
      response = [
        'HTTP/1.1 404 Not Found',
        'Content-Type: text/html',
        'Content-Length: 0',
        'Server: FakeCap by ron@greynoise.io',
        '',
        '',
      ].join("\r\n")
    end

    # Make the request loosely more valid (mostly fix newlines)
    if clean_up_http
      # Ensure that newlines are all `\r\n`
      request = request.split(/\r?\n/).join("\r\n")

      # If the request doesn't contain a double newline, ensure it ends with one
      until request.include?("\r\n\r\n")
        request.concat("\r\n")
      end

      # Do the response too
      unless response.nil?
        response = response.split(/\r?\n/).join("\r\n")

        until response.include?("\r\n\r\n")
          response.concat("\r\n")
        end
      end
    end

    return fake_binary(request, response, **kwargs)
  end
end
