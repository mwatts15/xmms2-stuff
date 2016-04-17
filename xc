#!/usr/bin/env ruby
require 'socket'
require 'readline'
require 'fiber'
require 'terminfo'
require 'xmmsclient'

$screen_width = TermInfo.screen_size[1]
Signal.trap('SIGWINCH', proc {
    $screen_width = TermInfo.screen_size[1]
    Readline.set_screen_size(TermInfo.screen_size[0], TermInfo.screen_size[1]) })
$SOCKET_PATH = `xce-serv`
$xce_connection = UNIXSocket.new($SOCKET_PATH)

$xc = Xmms::Client.new("xc")
begin
$xc.connect()
rescue Xmms::Client::ClientError => e
    $stderr.puts e
    `xmms2-launcher`
    ntries = 1
    while $? != 0
        if ntries > 4
            exit "Can't start xmms2d. Exiting."
        end
        $stderr.puts "Coludn't start the daemon, trying again..."
        sleep 3
        `xmms2-launcher -vvvv`
        ntries += 1
    end
    $stderr.puts "Connected."
end

def extract_medialib_info(id, fields)
    infos = $xc.medialib_get_info(id).wait.value
    fields = fields.map {|f| f.to_sym }
    fields.map do |field|
        values = infos[field]
        if not values.nil?
            my_value = values.first[1] # actual value from the top source [0]
            if field == :url
                my_value = decode_xmms2_url(my_value)
            end
            my_value.to_s.force_encoding("utf-8")
        else
            "no data"
        end
    end
end

$prompt = Fiber.new do
    while true
        input = Readline.readline('xmms2-coll> ', true)
        if input
            input << "\n"
            begin
                result = $xce_connection.send(input, Socket::MSG_PEEK)
            rescue Exception => e
                puts "got an exception #{e}"
            end

            if result != input.length
                break
            end
        else
            break
        end
        $receiver.transfer
    end
end

$receiver = Fiber.new do
    while true
        retry_count = 0
        begin
            tag = $xce_connection.recv_nonblock(4).unpack("A4")[0]
            length = $xce_connection.recv(4).unpack("L<")[0]
            value = ""
            if length > 0
                value = $xce_connection.recv(length)
            end

            case tag
            when "coll"
                fields = %w[id artist title album]
                collection = Marshal.restore(value)
                table = [fields] + collection.map { |id| extract_medialib_info(id, fields) }
                maxwidths = table.reduce(fields.map{ |f| f.length }) do |widths, row|
                    widths.zip(row.map{ |val| val.length }).map{|w| w.max}
                end
                table.each do |row|
                    puts row.zip(maxwidths).map { |pair|
                        pair[0].ljust(pair[1])
                    }.join("|")[0,$screen_width]
                end

            when "err"
                puts "Server error: " + value
            when "str"
                value.each_line do |line|
                    puts "!- " + line
                end
            when "ack"
            else
                puts "NONE OF THEM"
                puts tag + value
            end
        rescue IO::WaitReadable 
            if (retry_count < 5)
                retry_count += 1
                sleep(0.05)
                retry
            else
                $prompt.transfer
            end
        end
    end
end

$prompt.resume
