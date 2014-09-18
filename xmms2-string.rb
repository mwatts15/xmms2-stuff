#!/usr/bin/env ruby

require 'xmmsclient'
require 'prelude'
require 'socket'

$PIPE_PATH = "/tmp/#{ENV["USER"]}-xmms2-string-ipc-pipe"
$LOG_PATH = "#{ENV["HOME"]}/.config/xmms2/xmms2-string.log"
$LOG_FILE = nil

$xc = Xmms::Client.new("xmms2-stirg")
$CONNECTED=false
while not $CONNECTED
    begin
        $xc.connect
        $CONNECTED=true
        $LOG_FILE = File.open($LOG_PATH,"w")
        $xc.on_disconnect do 
            $LOG_FILE.print "Server died. Getting the hell out of Dodge.\n"
            exit
        end
    rescue Xmms::Client::ClientError => e
        $stderr.puts "Waiting for connect..."
        sleep 1
    end
end

def extract_medialib_info(id, *fields)
    infos = $xc.medialib_get_info(id).wait.value
    res = Hash.new

    fields = fields.map! {|f| f.to_sym }
    fields.each do |field|
        values = infos[field]
        if not values.nil?
            my_value = values.first[1] # actual value from the top source [0]
            if field == :url
                my_value = decode_xmms2_url(my_value)
            end
            res[field] = my_value.to_s.force_encoding("utf-8")
        end
    end
    res
end
$fields = [:title, :artist, :album]

$info = nil
$string = ""

def get_string(sep="::",undef_string="UNDEF")
    $current_id = $xc.playback_current_id.wait.value
    $info = extract_medialib_info($current_id, *$fields, :duration)
    info = $fields.map{|f| if $info[f] == nil then undef_string else $info[f] end}
    max_width = info.map{|k| k.real_length}.max
    begin
        string = info.map{|i| "#{i[0,max_width]}" }.join(sep) << "\n"
        max_width -= 1
    end while (string.real_length > 70)
    $string = string
end

$xc.broadcast_playback_current_id.notifier do |res|
    get_string
    true
end

#get_string

if not(File.exists?($PIPE_PATH) and File.pipe?($PIPE_PATH))
    begin
        File.unlink($PIPE_PATH)
    rescue => e
    end
    `mkfifo #{$PIPE_PATH}`
end

$stdout = File.open($PIPE_PATH,"w")
$stderr = $LOG_FILE

while true do
    begin
        p = $xc.playback_playtime.wait.value
    rescue TypeError => e
        p = $xc.playback_playtime.wait.value
    end

    begin
        if not ($info.nil? or p.nil?)
            d = $info[:duration].to_i
            r = [$string.length, (p * $string.length) / d].min
            print String.new($string).insert(r, "</fc>").insert(0,"<fc=#8aadb9>")
        end
    rescue Xmms::Client::ClientError => e
        $LOG_FILE.print "Server died. Dying.\n"
    rescue => e
        $LOG_FILE.print "Some error (#{e.inspect}): \n"
        $LOG_FILE.puts e.backtrace
        raise e
    end
    $stdout.flush
    sleep 1
end
