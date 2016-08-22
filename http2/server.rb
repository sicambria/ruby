require_relative 'helper'

#--------------------OPTIONS----------------------------
options = { port: 8080 }
OptionParser.new do |opts|
  opts.banner = 'Usage: server.rb [options]'

  opts.on('-s', '--secure', 'HTTPS mode') do |v|
    options[:secure] = v
  end

  opts.on('-p', '--port [Integer]', 'listen port') do |v|
    options[:port] = v
  end
end.parse!

#----------------------------------------------------------------
puts "Starting server on port #{options[:port]}"
server = TCPServer.new(options[:port])
#----------------------------------------------------------------
if options[:secure]
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.cert = OpenSSL::X509::Certificate.new(File.open('keys/server.crt'))
  ctx.key = OpenSSL::PKey::RSA.new(File.open('keys/server.key'))

  ctx.ssl_version = :TLSv1_2
  ctx.options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
  ctx.ciphers = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ciphers]

  ctx.alpn_select_cb = lambda do |protocols|
    raise "Protocol #{DRAFT} is required" if protocols.index(DRAFT).nil?
    DRAFT
  end

  ctx.tmp_ecdh_callback = lambda do |_args|
    OpenSSL::PKey::EC.new 'prime256v1'
  end

  server = OpenSSL::SSL::SSLServer.new(server, ctx)
end
#----------------------------------------------------------------
#----------------------------------------------------------------

loop do
  puts "Waiting..."
  ### ------------------NEW CONNECTION ------------------------
  sock = server.accept
  puts 'New TCP connection!'

  conn = HTTP2::Server.new
  conn.on(:frame) do |bytes|
    puts "Writing bytes: #{bytes.unpack("H*").first}"
    sock.write bytes
  end
  conn.on(:frame_sent) do |frame|
    puts "Sent frame: #{frame.inspect}"
  end
  conn.on(:frame_received) do |frame|
    puts "Received frame: #{frame.inspect}"
  end

  ### ------------------NEW STREAM ------------------------
  conn.on(:stream) do |stream|
    log = Logger.new(stream.id)
    req, buffer = {}, ''

    stream.on(:active) { log.info 'client opened new stream' }
    stream.on(:close)  { log.info 'stream closed' }

    stream.on(:headers) do |h|
      req = Hash[*h.flatten]
      log.info "request headers: #{h}"
    end

    #  stream.on(:half_close) do
    #    log.info 'client closed its end of the stream'
    #  end



    stream.on(:data) do |d|
      log.info "payload chunk: <<#{d}>>"
      buffer << d
    end

    response = nil
    if req[':method'] == 'GET' && req[':url'] == '.well-known/sila'
      log.info 'Received GET to COMMAND'
      response = 'COMMAND'
    else
      if req[':method'] == 'GET' && req[':url'] == '/sila2/org.sila-standard.release/common/needs_initalization/v1/'
        log.info 'Received GET to COMMAND'
        response = 'COMMAND'
      else
        if req[':method'] == 'GET' && req[':url'] == '/sila2/org.sila-standard.release/common/needs_initalization/v1/command/reset'
          log.info 'Received GET to COMMAND'
          response = 'COMMAND'
        else
          if req[':method'] == 'POST' && req[':url'] == 'POST'
            log.info "Received POST request, payload: #{buffer}"
            response = "Hello HTTP 2.0! POST payload: #{buffer}"
          else
            log.info 'Received INVALID COMMAND'
            response = 'INVALID COMMAND'
          end
        end
      end
    end


    #----------------------------------------------------------------
    stream.headers({
      ':status' => '200',
      'content-length' => response.bytesize.to_s,
      'content-type' => 'text/plain',
      }, end_stream: false)

      # split response into multiple DATA frames

      #stream.data(response.slice!(0, 5), end_stream: false)
      puts "stream send START"
      stream.data(response, end_stream: false)
      puts "stream send END"
      #stream.data(response)
    end

    while !sock.closed? && !(sock.eof? rescue true) # rubocop:disable Style/RescueModifier
      data = sock.readpartial(1024)
      puts "Received bytes: #{data.unpack("H*").first}"

      begin
        conn << data
        puts "conn-data end"

      rescue => e
        puts "rescue RUNS"
        puts "#{e.class} exception: #{e.message} - closing socket."
        e.backtrace.each { |l| puts "\t" + l }
        #sock.close

      end
      puts "end1"
    end
    puts "end2"


  puts "stream end"



  #----------------------------------------------------------------


  #----------------------------------------------------------------


end