#!/usr/bin/env ruby
# encoding: utf-8
require 'xmms2_utils'
require 'prelude'
require 'socket'

$PIPE_PATH = "/tmp/#{ENV["USER"]}-xmms2-string-ipc-pipe"
$LOG_PATH = "#{ENV["HOME"]}/.config/xmms2/xmms2-string.log"
$LOG_FILE = nil
$DISCONNECTED = false
$ACTIVE_COLOR = "#8aadb9"
$STOPPED_COLOR  = "#ff0000"
$xc = Xmms::client("xmms2-stirg")
$LOG_FILE = File.open($LOG_PATH,"w")
$xc.on_disconnect do
    $LOG_FILE.print "Server died. Getting the hell out of Dodge.\n"
    exit
    #$DISCONNECTED = true
end

$paused = false
$repeat = "off"
$stopped = false
$tiddle = 0

$fields = [:title, :artist, :album]

$info = nil
$string = ""

def get_string(sep="::",undef_string="UNDEF")
    $current_id = $xc.playback_current_id.wait.value
    $info = $xc.extract_medialib_info($current_id, *$fields, :duration)
    info = $fields.map{|f| if $info[f] == nil then undef_string else $info[f] end}
    max_width = info.map{|k| k.real_length}.max
    begin
        string = info.map{|i| "#{i[0,max_width]}" }.join(sep) << "\n"
        max_width -= 1
    end while (string.real_length > 70)
    string
end

def get_repeat_status
    pl = $xc.config_get_value('playlist.repeat_all').wait.value
    tr = $xc.config_get_value('playlist.repeat_one').wait.value
    if pl == "1"
        "playlist"
    elsif tr == "1"
        "track"
    else
        "off"
    end
end

def decode_playback_status(stat_code)
    if (stat_code == 1)
        paused = false
        stopped = false
    elsif (stat_code == 2)
        paused = true
    else
        stopped = true
        paused = true
    end
    return paused, stopped
end

$xc.broadcast_playback_current_id.notifier do |res|
    $string = get_string
    true
end

$xc.broadcast_config_value_changed.notifier do |res|
    $repeat = get_repeat_status
    true
end

$xc.broadcast_playback_status.notifier do |res|
    $paused, $stopped = decode_playback_status(res)
    update
    true
end

if not(File.exists?($PIPE_PATH) and File.pipe?($PIPE_PATH))
    begin
        File.unlink($PIPE_PATH)
    rescue => e
    end
    `mkfifo #{$PIPE_PATH}`
end

def get_xmobar_string(tiddle, playtime, track_info_string)
    str = "XMMS2"
    if not($info.nil? or playtime.nil? or track_info_string.length == 0)
        d = $info[:duration].to_i
        # The '- 1' is to prevent us from putting the </fc> on
        # a new line and mucking up xmobar's line-based parse
        if d > 0
            r = [track_info_string.length - 1, (playtime * track_info_string.length) / d].min
            r = [0, r].max
            play_anim = "-\\|/"
            play_anim_count = tiddle % play_anim.length
            start_symbol = if $stopped
                               "<fc=#{$STOPPED_COLOR}>*</fc>"
                           elsif $paused
                               "*"
                           else
                               "<fc=#{$ACTIVE_COLOR}>"+play_anim[play_anim_count] +"</fc>"
                           end
            repeat_symbol = if $repeat == "track"
                                "T"
                            elsif $repeat == "playlist"
                                "P"
                            else
                                "-"
                            end
            str = start_symbol + repeat_symbol + " " + String.new(track_info_string).insert(r, "</fc>").insert(0,"<fc=#{$ACTIVE_COLOR}>")
        end
    end
    str
end

def update
    $stdout.puts "XMMS2"
    begin
        p = $xc.playback_playtime.wait.value
    rescue TypeError => e
        p = $xc.playback_playtime.wait.value
    end
    if $stopped
        p = 0
    end

    begin
        $stdout.puts get_xmobar_string($tiddle, p, $string)
        $stdout.flush
    rescue Xmms::Client::ClientError => e
        $LOG_FILE.puts "Server died.\n"
    rescue Errno::EPIPE => e
        $LOG_FILE.puts "Broken pipe (#{e.inspect}): \n"
    rescue => e
        $LOG_FILE.print "Some error (#{e.inspect}): \n"
        $LOG_FILE.puts e.backtrace
        raise e
    end
end

$stdout = File.open($PIPE_PATH,"w")
$stderr = $LOG_FILE
$string = get_string
$repeat = get_repeat_status
$paused, $stopped = decode_playback_status($xc.playback_status.wait.value)
Process.daemon
while true do
    update
    $tiddle = $tiddle + 1
    sleep 1
end
