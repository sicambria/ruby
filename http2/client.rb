require_relative 'helper'

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: client.rb [options]'

  opts.on('-d', '--data [String]', 'HTTP payload') do |v|
    #options[:payload] = "SiLA consumer that wants to reset"
    options[:payload] = v
  end
end.parse!

uri = URI.parse(ARGV[0] || 'http://localhost:8080/.well-known/sila')
tcp = TCPSocket.new(uri.host, uri.port)
sock = nil
sock = tcp

#------------------------------SSL-TLS----------------------------------
# if uri.scheme == 'https'
#   ctx = OpenSSL::SSL::SSLContext.new
#   ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
#
#   ctx.npn_protocols = [DRAFT]
#   ctx.npn_select_cb = lambda do |protocols|
#     puts "[CL] NPN protocols supported by server: #{protocols}"
#     DRAFT if protocols.include? DRAFT
#   end
#
#   sock = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
#   sock.sync_close = false
#   sock.hostname = uri.hostname
#   sock.connect
#
#   if sock.npn_protocol != DRAFT
#     puts "[CL] Failed to negotiate #{DRAFT} via NPN"
#     exit
#   end
# else
#   sock = tcp
# end

#----------------------------------------------------------------

conn = HTTP2::Client.new

#----------------------------CONN. EVENTS----------------------------

conn.on(:frame) do |bytes|
  puts "Sending bytes: #{bytes.unpack("H*").first}"
  sock.print bytes
  sock.flush
end

conn.on(:frame_sent) do |frame|
  puts "[OUT] Sent frame: #{frame.inspect}"
end

conn.on(:frame_received) do |frame|
  puts "[IN] Received frame: #{frame.inspect}"
end

conn.on(:promise) do |promise|
  promise.on(:headers) do |h|
    log.info "[CL] promise headers: #{h}"
  end

  promise.on(:data) do |d|
    log.info "[CL] promise data chunk: <<#{d.size}>>"
  end
end

conn.on(:altsvc) do |f|
  log.info "[CL] received ALTSVC #{f}"
end

# ------------ LOOP ----------------
loop do
  stream = conn.new_stream
  log = Logger.new(stream.id)

  #----------------------------STREAM EVENTS----------------------------

  stream.on(:close) do
    log.info '[CL] stream closed'
    sock.close
  end

  stream.on(:half_close) do
    log.info '[CL] closing client-end of the stream'
  end

  stream.on(:headers) do |h|
    log.info "[CL] response headers: #{h}"
  end

  stream.on(:data) do |d|
    log.info "[CL] response data chunk: <<#{d}>>"
  end

  stream.on(:altsvc) do |f|
    log.info "[CL] received ALTSVC #{f}"
  end

  #----------------------------------------------------------------
  puts "=== MAIN MENU ==="
  #----------------------------------------------------------------

  begin
    puts "g - GET"
    puts "p - POST"
    puts "s - SUBSCRIBE"
    puts "q - QUIT"
    choice = gets.chomp
  end until choice == "g" || choice == "p" || choice == "s" || choice == "q"

  if choice=="q"
    exit
  end

  #--------GET--------
  if choice=="g"

    head = {
        ':scheme' => uri.scheme,
        ':method' => 'GET',
        # ':method' => (options[:payload].nil? ? 'GET' : 'POST'),
        ':authority' => [uri.host, uri.port].join(':'),
        ':path' => '/.well-known/sila',
        'accept' => '*/*',
    }

    puts 'GET status'
    stream.headers(head, end_stream: true)
    puts 'GET status SENT'

  end # GET end


  #-------POST---------
  if choice=="p"

    head = {
        ':scheme' => uri.scheme,
        ':method' => 'POST',
        ':authority' => [uri.host, uri.port].join(':'),
        ':path' => '/.well-known/sila',
        'accept' => '*/*',
    }

    puts 'Sending HTTP 2.0 POST request'
    stream.headers(head, end_stream: true)
    stream.data(options[:payload])
  end # POST end


  #-------SUBSCRIBE---------
  if choice=="s"

    head = {
        ':scheme' => uri.scheme,
        ':method' => 'GET',
        ':authority' => [uri.host, uri.port].join(':'),
        ':path' => '/.well-known/sila/clock',
        'accept' => '*/*',
    }

    puts 'SUBSCRIBE'
    stream.headers(head, end_stream: true)
  end # SUBSCRIBE end


  sleep 3

  #---------------------SOCKET READ--------------------------
  while !sock.closed? && !sock.eof?
    data = sock.read_nonblock(1024) # was 1024 before
    puts "Received bytes: #{data.unpack("H*").first}"

    begin
      puts "conn-data-start"
      conn << data
      puts "conn-data-end"

    rescue => e
      puts "#{e.class} exception: #{e.message} - closing socket."
      e.backtrace.each { |l| puts "\t" + l }
      sock.close
      #break
    end # conn-data-start - begin end
  end # socket while end
end # MAIN MENU loop end
