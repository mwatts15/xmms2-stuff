#!/usr/bin/env ruby
require 'xmmsclient'
require 'readline'

$xc = Xmms::Client.new("rpncol")
$xc.connect() or exit "*sign*...fuck it"

class Collection < Xmms::Collection
    def initialize (type)
        @top=0
        super(type)
    end
    def to_s
        "<Collection "+
        "type:#{self.type} "+
        "field:#{self.attributes["field"].to_s} "+
        "value:#{self.attributes["value"].to_s} "+
        "operands:#{self.operands.to_a}>"
    end
    def print_coll
        fields = %w[artist album title]
        puts "???"
        $xc.coll_query_info(self,fields).wait.value.each do |dict|
            puts "[#{fields.collect {|f| dict[f.to_sym].to_s}.join(", ")}]"
        end
    end
    def push(o)
        case type
        when Xmms::Collection::TYPE_GREATER,
            Xmms::Collection::TYPE_EQUALS,
            Xmms::Collection::TYPE_SMALLER,
            Xmms::Collection::TYPE_MATCH
            if @top == 0
                if (!o.is_a?(Symbol))
                    $stderr.puts "Invalid \"field\" argument"
                else
                    self.attributes["field"] = o.to_s
                end
            elsif @top == 1
                self.attributes["value"] = o.to_s
            end
            @top += 1
            self
        else
            operands.push(o)
        end
        self
    end
    alias :<< :push
end
$empty_sym = [:empty, ['~']]

$classes = [:op, :field, :quant]

$syms = { :op => [[:op_and, %w<a and>, Xmms::Collection::TYPE_INTERSECTION],
            [:op_or, %w<o or>, Xmms::Collection::TYPE_UNION], 
            [:op_andn, %w<an andn>, Xmms::Collection::TYPE_INTERSECTION],
            [:op_orn, %w<on orn>, Xmms::Collection::TYPE_UNION],
            [:op_not, %w<n not>, Xmms::Collection::TYPE_COMPLEMENT]],

          :field => [[:bitrate, %w<br bitrate>],
            [:artist, %w<ar artist>],
            [:title, %w<ti title>],
            [:url, %w<u url>],
            [:album, %w<al album>]],

          :quant => [[:q_gt, %w<\> gt>, Xmms::Collection::TYPE_GREATER],
            [:q_lt, %w<\< lt>, Xmms::Collection::TYPE_SMALLER],
            [:q_match, %w<m match>, Xmms::Collection::TYPE_MATCH],
            [:q_eq, %w<= : eq>, Xmms::Collection::TYPE_EQUALS]],
          :cmd => [[:c_clear_stack, %w<cl>],
            [:c_print_head, %w<p>],
            [:c_print_stack, %w<ps>],
            [:c_print_coll, %w<pc>]]}

# returns the token associated with
# a given string
$token_table =
($syms.values.reduce(:+) << $empty_sym).reduce(Hash.new) do |h, s|
    token = s[0]
    opers = s[1]
    opers.each do |op|
        h[op] = token
        #puts "op #{op} -- #{token}"
    end
    h
end
$coll_types =
$syms.values_at(:op, :quant).reduce(Hash.new) do |h,s|
    tokens = s.transpose[0]
    types = s.transpose[2]
    tokens.zip(types).collect do |pair|
        h[pair[0]] = pair[1]
    end
    h
end

$unary_symbolic_ops = %w{< > = !}

$pats = $syms.reduce(Hash.new) do |h, p|
    h[p[0]] = p[1].transpose[1].flatten.join("|")
    h
end
$pats[:fn] = $pats.values_at(:op, :quant).join("|")
$pats[:str] = '(\\\n|[^\n])*'
$pats[:int] = '(-|\+)?\d+'
$token_pat = $token_table.keys.join("|")

#puts $classes
#puts $pats.values
#puts $token_pat
#puts $token_table.values
#puts $coll_types

# extracts the actual string
# from a string escaped operator
def extract_string_literal(string)
    string
end


#
# returns the tokens belonging
# to the string.
# We allow multiple tokens to be returned
# in order to make aliasing easier
def get_token(string)
    case string
    when /\A(#{$token_pat})\Z/
        $token_table[$&]
    when /\A#{$pats[:int]}\Z/
        $&.to_i
    when /\A#{$pats[:str]}\Z/
        # we do this to piggy-back on ruby's own
        # types without needing to write tokens
        # for our own
        extract_string_literal($&)
    else
        nil
    end
end

def pre_proc(string)
    newparts = Array.new
    uso = $unary_symbolic_ops.collect{|o| "\\" + o}.join("|")
    case string
    when /\A(#{$pats[:fn]})\Z/
        # this is how we do postfix
        # because of currying, the operator
        # will get put on the curry stack
        # waiting for arguments on its right
        # side instead of taking them off the
        # stack
        #newparts << "~"
        newparts << $1
    when /\A(#{uso})(#{$string_pat})\Z/
        newparts << $2
        newparts << $1
    when /\A\Z/
        nil
    else
        newparts << string
    end
    newparts
end

# we simplify the process by
# stipulating that no tokens
# can contain newlines, which
# is easy enough
def tokenize(string)
    # split by newlines and surrounding
    # whitespace
    parts = string.split(/\s*\n\s*/)
    tokens = Array.new
    parts.each do |part|
        pre_proc(part).each do |p|
            tokens << get_token(p)
        end
    end
    tokens
end

def build_collection (input)
    vstack = Array.new
    class <<vstack
        def empty?
            self.length == 0 or self.last == :empty
        end
        def push(item)
            if self.last == :empty
                self[-1] = item
            else
                super item
            end
        end
        def pop
            if self.last == :empty
                nil
            else
                super
            end
        end
        def length
            self.reverse.take_while{|e| e != :empty}.length
        end
        # _pops_ at most num operands from the stack
        def get_ops(num)
            operands = Array.new
            while !empty? and !(operands.length >= num)
                operands << pop
            end
            operands.reverse
        end
        alias :<< :push
    end
    opstack = Array.new # [ [:name [<arguments taken>] <arguments needed>] ]

    nary_op = Proc.new do |num_ops, token|
        c = Collection.new($coll_types[token])
        if $syms[:quant].transpose[0].include?(token)
            c.operands << Xmms::Collection.universe
        end
        operands = vstack.get_ops(num_ops)
        operands.each {|op|c << op}
        if operands.length < num_ops
            opstack << [c, num_ops - operands.length]
        else
            vstack << c
        end
    end
    
    input.each do |line|
        line.chomp! # in case we're reading from stdin
        pre_proc(line).map{|p|get_token(p)}.each do |t|
            case t
                # two-operand collections combinators
            when *$syms[:op].transpose[0], *$syms[:quant].transpose[0]
                nary_op[2, t]
            when :c_clear_stack
                vstack.clear
            when :c_print_head
                puts vstack.last
            when :c_print_coll
                vstack.last.is_a?(Collection) and vstack.last.print_coll
            when :c_print_stack
                puts "HEAD", vstack.reverse, "----"
            else
                vstack << t
            end

            # check delayed/curried operations
            while !opstack.empty? and !vstack.empty?
                operands = vstack.get_ops(opstack.last[1])
                operands.each{|op| opstack.last[0] << op}
                opstack.last[1] -= operands.length
                if opstack.last[1] == 0
                    vstack << opstack.pop[0]
                end
            end
        print "vstack = #{vstack}\nopstack = #{opstack}\ntoken = #{t}\n"
        end
        #puts vstack.last
    end
    vstack.pop
end
class Rl
    def each
        while true
            input = Readline.readline('xmms2-coll> ', true)
            input and yield(input) or break
        end
    end
end
rl = Rl.new
build_collection(rl)
