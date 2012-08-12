#!/usr/bin/env ruby
require 'xmmsclient'
require 'uri'
##########################
# simple xmms2 script    #
# for dmenu              #
##########################

#$CONFIG = File.join(Dir.home + ".config/dxmms2")
# default configs
# {{{
$SCREEN_WIDTH=1366
$FONT_WIDTH=10 #in pixels
$BG_COLOR='"#000000"'
$FG_COLOR='"#dc322f"'
$SEL_BG_COLOR=$FG_COLOR
$SEL_FG_COLOR=$BG_COLOR
$FONT='"Sazanami Mincho":pixelsize=' + $FONT_WIDTH.to_s
$LIST_ENTRIES_PER_PAGE = 15
# }}}

#if [ -e $CONFIG ] ; then
    #source $CONFIG
#fi
class String
    def alignr(r, w)
        r.force_encoding("utf-8")
        #self.force_encoding("utf-8")
        its, mine = [r, self].collect do |op|
            res = 0
            op.bytes {|b| res+=1}
            res -= op.length
            res
        end
        puts w
        self + r.rjust(2 * (w/$FONT_WIDTH) - self.length - its / 2 - mine / 2)
    end
    def to_perc
        if self.ends_width("%")
            self.to_f / 100.0
        else
            self.to_f * 100
        end
    end
    alias :| alignr
end

def my_dmenu (entries, prompt='dxmms2', height=4, width=$SCREEN_WIDTH)
width=$SCREEN_WIDTH
    res = ""
    entries.collect! do |line|
        r, l = line.split("|||")
        l ? r.alignr(l,width) : r
    end
    cmdline = "dmenu -p \"#{prompt}\" -nf #{$FG_COLOR} \
    -nb #{$BG_COLOR} \
    -sb #{$SEL_BG_COLOR} \
    -sf #{$SEL_FG_COLOR} \
    -i -l #{height} \
    -w #{width} \
    -fn #{$FONT}"
    IO.popen(cmdline, "w+") do |io|
        io.print(entries.join("\n"))
        io.close_write
        res = io.gets
    end
    res.to_s.chomp
end

# returns a hash of the passed in fields
# with the top values for the fields
def extract_medialib_info(id, fields)
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

def pl_list
    morestring="--More--"
    backstring="--Back--"
    listing=1
    pos = nil
    list_start = $pl.current_pos.wait.value[:position]
    while ( listing == 1 ) do
        start_clamped = false
        end_clamped = false
        entries = $pl.entries.wait.value
        items = Array.new

        #clamps start
        (list_start <= 0) and (list_start = 0 ; start_clamped = true)

        list_end = list_start + $LIST_ENTRIES_PER_PAGE

        #clamps end
        (list_end > entries.length) and (list_end = entries.length ; end_clamped = true)


        nw = list_end.to_s.length
        i = list_start

        entries[list_start..list_end].each do |id| 
            my_info = extract_medialib_info(id, ["artist", "title", "url"])
            artist_part = "#{i.to_s.rjust(nw)}. #{my_info[:artist]}"
            some_title = (my_info[:title] or File.basename(my_info[:url]))
            items << artist_part + "|||" + some_title#.dmenu_alignr(artist_part)
            i += 1
        end

        if not start_clamped
            items << backstring
        end

        if not end_clamped
            items << morestring
        end

        choice = my_dmenu(items, "Track:", items.length).gsub(/^\s+|\s+$/, "")
        pos = choice[/^-?\d+|#{morestring}|#{backstring}/]
        if (not start_clamped) and pos == backstring
            list_start -= 15
        elsif not end_clamped and pos == morestring
            list_start += 15
        else
            listing=0
        end
    end
    if pos.nil? then return nil end

    pos = pos.to_i
    if pos < 0 then entries.length + pos else pos end
end

def decode_xmms2_url (url)
    URI.decode_www_form_component(url)
    #echo "$(perl -MURI::Escape -e 'print uri_unescape($ARGV[0]);' "$url")" 
end

$commands=%w<toggle list +fav prev next stop info change-playlist clear edit-metadata search>

$xc = Xmms::Client.new("dxmms2")
$xc.connect(ENV["XMMS_PATH"])
$pl = $xc.playlist

while (true) do
    command = my_dmenu($commands).chomp
    case command
    when "list"
        # requires 
        #  CLASSIC_LIST=true
        #  CLASSIC_LIST_FORMAT=${artist}::${title}
        # in .config/xmms2/clients/nycli.conf
        pos = pl_list
        if not pos.nil?
            puts "moving to positon #{pos}"
            res = $xc.playlist_set_next(pos).wait.value
            #puts res
            $xc.playback_tickle.wait
            $xc.playback_start.wait
        end
        break
    when "info"
        entries = $pl.entries.wait.value
        if not entries.nil?
            pos = pl_list
            id = entries[pos]
            info = extract_medialib_info(id, %w<artist title album tracknr favorite url>)
            my_dmenu(info.map {|k,v| k.to_s + "|||" + v}, "Info", info.size, 1000)
        end
        break
        #when "+fav"
        #id=`xmms2 info | grep "server.* id " | grep -o "[[:digit:]]*$"`
        #fav=`xmms2 info | grep "cli.* favorite " | grep -o "[[:digit:]]*$"`
        #fav=$((fav + 1))
        #xmms2 server property $id favorite $fav
    when "search"
        search_fields = %w<artist title album>
        cachedir = File.join(Dir.home, ".cache/lister")
        search_options = Hash.new
        search_fields.each do |f|
            File.open(File.join(cachedir, f), "r") do |file|
                lines = Hash.new
                file.each do |line|
                    parts = line.chomp.split(/\0/, 2)
                    lines[parts[0]] = parts[1]
                end
                search_options[f] = lines
            end
        end
        search_str = ""

        search_parts = Hash.new(Array.new)
        selecting = true
        while selecting do
            field = my_dmenu(search_fields, "Attribute:")
            if not field.empty?
                opt = search_options[field]
                search_str << " " + field + ":"
                value = my_dmenu(opt.keys, search_str[-15..-1], 15)
                search_str << "<#{value}>"
                if not value.empty? and opt.has_key?(value)
                    search_parts[field] += opt[value].split(/\0/)
                end
            else
                selecting = false
            end
            puts search_parts
            puts search_str
        end
        search_str = search_parts.collect {|k,v| v.collect{|val| "#{k}:'#{val}'"}.join(" OR ")}.join(" AND ")

        break
        #when "change-playlist"
        #pls=`xmms2 playlist list`
        #nitems=`echo "$pls"|wc -l`
        #pl=`echo "$pls" | cut -c 3- | my_dmenu "Playlist: " ${nitems}`
        #xmms2 playlist switch $pl
        #when edit-metadata
        #url="$(decode_xmms2_url "`xmms2 info | grep url | sed 's/.*=[[:space:]]// ; s%^file://%% ; s%+% %'g`")"
        #picard "$url"
    else
        if not command.empty?
            `xmms2 #{command}`
        end
        break
    end
end
