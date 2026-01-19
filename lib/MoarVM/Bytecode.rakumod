# An attempt at providing introspection into the MoarVM bytecode format

#use v6.e.PREVIEW;  # We use new Format support

# Faster formatted values!
my &formatx   := { sprintf '%x', $_ };     # Format.new('%x');
my &format4x  := { sprintf '%4x', $_ };    # Format.new('%4x');
my &format8d  := { sprintf '%8d', $_ };    # Format.new('%8d');
my &format12s := { sprintf '%-12s', $_ };  # Format.new('%-12s');

# Even faster '%02x' formatting
my str @lookup = <0 1 2 3 4 5 6 7 8 9 a b c d e f>;
my sub format02x(uint8 $value) {
    @lookup[$value +> 4] ~ @lookup[$value +& 0x0f]
}

use MoarVM::Ops;
use List::Agnostic:ver<0.0.3+>:auth<zef:lizmat>;
use paths:ver<10.1+>:auth<zef:lizmat>;

my constant @localtype = <
  0      int8 int16 int32 int64 num32 num64 str    obj    9
  10     11   12    13    14    15    16    uint8  uint16 uint32
  uint64
>;
my constant LE      = LittleEndian;        # make shorter lines
my constant MAGIC   = 724320148219055949;  # "MOARVM\r\n" as a 64bit uint
my constant IDMAX   = 51200;               # max offset for MAGIC finding
my constant EXTOPS  = 1024;                # opcode # of first extension op
my constant NONAMED = Map.new;             # no named args in callsite

my constant BON  = "\e[1m";   # BOLD ON
my constant BOFF = "\e[22m";  # BOLD OFF

# From src/core/callsite.h
my constant MVM_CALLSITE_ARG_OBJ     =   1; # object
my constant MVM_CALLSITE_ARG_INT     =   2; # native integer, signed
my constant MVM_CALLSITE_ARG_NUM     =   4; # native floating point number
my constant MVM_CALLSITE_ARG_STR     =   8; # native NFG string (MVMString REPR)
my constant MVM_CALLSITE_ARG_LITERAL =  16; # literal
my constant MVM_CALLSITE_ARG_NAMED   =  32; # named argument
my constant MVM_CALLSITE_ARG_FLAT    =  64; # flattened argument
my constant MVM_CALLSITE_ARG_UINT    = 128; # native integer, unsigned

#- general helper subs ---------------------------------------------------------
my sub dumphex(Buf:D $blob, uint $start, uint $bytes, @on?) {
    my uint $base = $start +& 0x0fffffff0;
    my uint $last = $start + $bytes;

    my &format-offset := { sprintf '%' ~ formatx($last).chars ~ 'x', $_ };
    # Format.new('%' ~ formatx($last).chars ~ 'x');

    sub with-highlight(uint $offset is copy) {
        my str @parts = format-offset($offset), "";

        for ^16 {
            my $cell := format02x($blob[$offset]);

            if $offset < $start || $offset >= $last {
                $cell := "  ";
            }
            elsif @on && @on[0] == $offset {
                @on.shift;
                $cell := BON ~ $cell ~ BOFF;
            }

            @parts.push: $cell;
            ++$offset;
        }
        @parts.join(" ")
    }

    sub without-highlight(uint $offset is copy) {
        my str @parts = format-offset($offset), "";

        for ^16 {
            @parts.push: ($offset < $start || $offset >= $last)
              ?? "  "
              !! format02x($blob[$offset]);
            ++$offset;
        }
        @parts.join(" ")
    }

    my str @parts;
    my uint $offset = $base;
    my &oneline := @on ?? &with-highlight !! &without-highlight;
    while $offset < $last {
        @parts.push: oneline($offset);
        $offset += 16;
    }

    @parts.join("\n")
}

#-  MoarVM::Bytecode::Iterator -------------------------------------------------
my class MoarVM::Bytecode::Iterator does Iterator {
    has      $!source is built(:bind);
    has      $!opcodes;
    has uint $!elems;
    has uint $!offset;

    method TWEAK() {
        $!opcodes := $!source.opcodes;
        $!elems    = $!opcodes.elems;
    }

    method pull-one() {
        my uint $offset = $!offset;

        if $offset < $!elems {
            my $source := $!source;
            my $op := $source.op($!opcodes.read-uint16($offset, LE));
            if $op ~~ Failure {
                $!offset = $!elems;
            }
            else {
                $!offset = $offset + $op.bytes($source, $offset);
            }
            $op
        }
        else {
            IterationEnd
        }
    }
}

#- MoarVM::Bytecode::Filename --------------------------------------------------
# Role to mixin name for objects that sometimes have a filename
my role MoarVM::Bytecode::Filename {
    has $.filename;
}

#- MoarVM::Bytecode::Name ------------------------------------------------------
# Role to mixin name for objects that sometimes have a name
my role MoarVM::Bytecode::Name {
    has $.name;
}

#- MoarVM::Bytecode::Argument --------------------------------------------------
my class MoarVM::Bytecode::Argument is Int {
    method name(--> "") { }

    method flags()         { self                                  }
    method is-positional() { self.name eq ""                       }
    method is-literal()    { self +& MVM_CALLSITE_ARG_LITERAL && 1 }
    method is-flattened()  { self +& MVM_CALLSITE_ARG_FLAT    && 1 }

    method type() {
        self +& MVM_CALLSITE_ARG_STR
          ?? str
          !! self +& MVM_CALLSITE_ARG_INT
            ?? int
            !! self +& MVM_CALLSITE_ARG_UINT
              ?? uint
              !! self +& MVM_CALLSITE_ARG_NUM
                ?? num
                !! Mu  # assume MVM_CALLSITE_ARG_OBJ
    }

    multi method gist(MoarVM::Bytecode::Argument:D:) {
        my str $type = self.type.^name;
        my str @parts = $type eq "Mu" ?? "object" !! $type;

        @parts.push: self.name ?? ":$.name" !! "positional";
        @parts.push: "flattened" if self.is-flattened;

        @parts.join(" ")
    }
}

#- MoarVM::Bytecode::Callsite --------------------------------------------------
my class MoarVM::Bytecode::Callsite {
    has uint $.bytes;
    has      @.arguments is built(:bind);
    has      %.named     is built(:bind);

    method has-named-arg(str $name) { %!named{$name}:exists }

    multi method gist(MoarVM::Bytecode::Callsite:D:) {
        @!arguments.map({
            my str $type = .type.^name;
            my str $name = .name;
            my str @parts;

            @parts.push($type) if $type ne 'Mu' && !.is-literal;
            @parts.push($name
              ?? ":$name"
              !! .is-literal
                ?? $type eq 'str'
                  ?? "''"
                  !! $type eq 'Mu'
                    ?? 'O'
                    !! 'N'
                !! .is-flattened
                  ?? '|%'
                  !! '$'
            );
            @parts.join(" ");
        }).join(", ")
    }
}

#- MoarVM::Bytecode::ExtensionOp -----------------------------------------------
my class MoarVM::Bytecode::ExtensionOp {
    has str  $.name;
    has uint $.index;
    has uint $.bytes;
    has Buf  $.descriptor;

    multi method gist(MoarVM::Bytecode::ExtensionOp:D: :$verbose) {
        my str @parts = format4x($!index), format12s($!name);

        @parts.push: "($!bytes bytes)" if $verbose;
        @parts.join(' ')
    }

    method adverbs(             ) { BEGIN Map.new }
    method annotation( --> ""   ) {               }
    method bytes($, $           ) { $!bytes       }
    method is-dequence(--> False) {               }
    method operands(            ) { ()            } # XXX for now
}

#- MoarVM::Bytecode::Frame -----------------------------------------------------
my class MoarVM::Bytecode::Frame does Iterable {
    has        $.M handles <callsites op>;
    has uint32 $.index;
    has str    $.cuid;
    has uint16 $.outer-index;
    has uint16 $.flags;
    has uint32 $.sc-dependency-index;
    has uint32 $.sc-object-index;
    has        $.opcodes    is built(:bind);
    has        @.statements is built(:bind);
    has        @.locals     is built(:bind);
    has        @.lexicals   is built(:bind);
    has        @.handlers   is built(:bind);

    method name(    --> "") { }
    method filename(--> "") { }

    method no-outer()         { $!outer-index == $!index }
    method has-exit-handler() { $!flags +& 1             }
    method is-thunk()         { $!flags +& 2 && 1        }

    method is-inlineable() {
        self.opcodes.elems <= 192 && !(self.first(*.not-inlineable))
    }

    method opcodes() {
        $!opcodes ~~ Callable
          ?? ($!opcodes := $!opcodes())
          !! $!opcodes
    }

    method iterator() { MoarVM::Bytecode::Iterator.new(:source(self)) }

    multi method hexdump() {
        my $opcodes := self.opcodes;
        dumphex($opcodes, 0, $opcodes.elems)
    }
    multi method hexdump(:$highlight!) {
        return self.hexdump unless $highlight;

        my      $M       := $!M;
        my      $opcodes := self.opcodes;
        my uint $elems    = $opcodes.elems;
        my uint $offset;
        my uint @on;

        while $offset < $elems {
            my $op := $M.op($opcodes.read-uint16($offset, LE));
            if $op ~~ Failure {
                $offset = $elems;
            }
            else {
                @on.push: $offset    ;
                @on.push: $offset + 1;
                $offset = $offset + $op.bytes($M, $offset);
            }
        }
        dumphex($opcodes, 0, $opcodes.elems, @on)
    }

    multi method de-compile(:$verbose) {
        self.map(*.gist(:$verbose)).join("\n")
    }
    multi method de-compile($matcher, :$verbose) {
        self.map({
            my str $gist = .gist(:$verbose);
            $matcher($gist.substr(5,14).trim-trailing)
              ?? $gist.substr(0,5)
                   ~ BON
                   ~ $gist.substr(5,14)
                   ~ BOFF
                   ~ $gist.substr(19)
              !! $gist
        }).join("\n")
    }

    multi method gist(MoarVM::Bytecode::Frame:D: :$verbose) {
        my str @parts = format4x($!cuid);

        if self.filename -> $filename is copy {
            my str $line = @!statements ?? ":@!statements.head.line()" !! "";
            @parts.push: $verbose
              ?? "$filename, line $line\n    "
              !! "$filename.split("/").tail()$line";

            if self.name -> $name {
                @parts.push: qq/"$name"/;
            }
        }

        @parts.push: "inlineable"       if self.is-inlineable;
        @parts.push: "no-outer"         if self.no-outer;
        @parts.push: "has-exit-handler" if self.has-exit-handler;
        @parts.push: "is-thunk"         if self.is-thunk;

        @parts.push: "$.opcodes.elems() bytes";
        @parts.push: "@!statements.elems() stmts" if @!statements.elems > 0;

        @parts.join(" ");
    }
}

#- MoarVM::Bytecode::Handler --------------------------------------------
my class MoarVM::Bytecode::Handler {
    has uint32 $.start-protected-region;
    has uint32 $.end-protected-region;
    has uint32 $.category-mask;
    has uint16 $.action;
    has uint16 $.register-with-block;
    has uint32 $.handler-goto;
    has uint16 $.extra;
}

#- MoarVM::Bytecode::Local -----------------------------------------------------
my class MoarVM::Bytecode::Local {
    has str $.name;
    has str $.type;

    multi method gist(MoarVM::Bytecode::Local:D:) {
        "$!type $!name"
    }
}

#- MoarVM::Bytecode::Lexical ---------------------------------------------------
my class MoarVM::Bytecode::Lexical {
    has str    $.name;
    has str    $.type;
    has uint16 $.flags;
    has uint32 $.sc-dependency-index;
    has uint32 $.sc-object-index;

    method is-static-value()  { $!flags == 0 }
    method is-container-var() { $!flags == 1 }
    method is-state-var()     { $!flags == 2 }

    multi method gist(MoarVM::Bytecode::Lexical:D:) {
        ($!flags ?? $!flags == 1 ?? 'container ' !! 'state ' !! 'static ')
         ~ " $!type $!name";
    }
}

#- MoarVM::Bytecode::Statement -------------------------------------------------
# Encapsulate statement (aka annotated bytecode information)
my role MoarVM::Bytecode::Statement {
    has uint32 $.line;
    has uint32 $.offset;

    multi method gist(MoarVM::Bytecode::Statement:D:) {
        "line $!line offset $!offset"
    }
}

#- MoarVM::Bytecode::Strings ---------------------------------------------------
# Encapsulate the string heap as a Positional
my class MoarVM::Bytecode::Strings does List::Agnostic {
    has        $!M       is built;
    has uint32 @!offsets is built;
    has uint   $.elems;
    has uint   $.bytes;

    my int @extra = 4, 7, 6, 5;

    method new($M) {
        my uint32 @offsets;

        my uint $start  = $M.string-heap-offset;
        my uint $offset = $start;
        my uint $elems  = $M.string-heap-entries;
        my uint $i;
        while $i < $elems {
            @offsets.push: $offset;

            my uint $bytes = $M.uint32($offset) +> 1;
            $offset = $offset + $bytes + @extra[$bytes +& 0x03];
            ++$i;
        }

        self.bless(:$M, :@offsets, :$elems, :bytes($offset - $start))
    }

    method AT-POS(Int:D $pos) {
        if $pos < 0 || $pos >= $!elems {
            Nil
        }
        else {
            my uint32 $offset = @!offsets[$pos];
            my uint32 $bytes  = $!M.uint32($offset);
            $bytes +& 1
              ?? $!M.subbuf($offset + 4, $bytes +> 1).decode
              !! $!M.slice( $offset + 4, $bytes +> 1).chrs
        }
    }

    method elems() { $!elems }  # required by Array::Agnostic

    method gist(MoarVM::Bytecode::Strings:D:) {
        "String Heap: $!elems different strings, $!bytes bytes"
    }
}

#- MoarVM::Bytecode::Frames ----------------------------------------------------
# Encapsulate the frames heap as a Positional
my class MoarVM::Bytecode::Frames does List::Agnostic {
    has      $!M      is built;
    has      @!frames is built;
    has uint $.elems;
    has uint $.bytes;
    has uint $.total-locals;
    has uint $.total-lexicals;
    has uint $.total-handlers;
    has uint $.total-lexical-values;
    has uint $.total-local-debug-names;

    method new($M) {
        my $bc := $M.bytecode;

        my uint32 @frames;
        my uint $total-locals;
        my uint $total-lexicals;
        my uint $total-handlers;
        my uint $total-lexical-values;
        my uint $total-local-debug-names;

        my uint $start  = $M.frames-data-offset;
        my uint $offset = $start;
        my uint $elems  = $M.frames-data-entries;
        my uint $i;
        while $i < $elems {
            @frames.push: $offset;

            my $num-locals   := $bc.read-uint32($offset +  8, LE);
            my $num-lexicals := $bc.read-uint32($offset + 12, LE);
            my $num-handlers := $bc.read-uint32($offset + 34, LE);
            my $num-values   := $bc.read-uint16($offset + 40, LE);
            my $num-names    := $bc.read-uint16($offset + 50, LE);

            $offset = $offset + 54 + $num-locals * 2 + $num-lexicals * 6;

            # Handlers have a variable data size in version 7, depending on
            # a bit in the category mask
            for ^$num-handlers {
                $offset = $offset  # check category mask
                  + ($bc.read-uint32($offset + 8, LE) +& 4096 ?? 22 !! 20);
            }

            $offset = $offset + $num-values * 12 + $num-names * 6;

            # Update statistics
            $total-locals            += $num-locals;
            $total-lexicals          += $num-lexicals;
            $total-handlers          += $num-handlers;
            $total-lexical-values    += $num-values;
            $total-local-debug-names += $num-names;

            ++$i;
        }

        self.bless(
          :$M, :@frames, :$elems, :bytes($offset - $start),
          :$total-locals, :$total-lexicals, :$total-handlers,
          :$total-lexical-values, :$total-local-debug-names
        )
    }

    method AT-POS(Int:D $pos) {
        if $pos < 0 || $pos >= $!elems {
            Nil
        }
        else {
            (my $frame := @!frames[$pos]) ~~ Int
              ?? (@!frames[$pos] := self!make-frame-at($frame, $pos))
              !! $frame
        }
    }

    method elems() { $!elems }  # required by Array::Agnostic

    method reify-all(:$batch = 4) {
        my @frames is List = @!frames.pairs.hyper(:$batch).map: {
            (my $offset := .value) ~~ Int
              ?? self!make-frame-at($offset, .key)  # need to reify
              !! $offset                            # already reified
        }
        @!frames := @frames;
    }

    method !make-frame-at(uint $offset is copy, uint $index) {
        my $M  := $!M;
        my $bc := $M.bytecode;
        my $st := $M.strings;

        my $opcodes-offset := $M.opcodes-offset + $bc.read-uint32($offset,LE);
        my $opcodes-length := $bc.read-uint32($offset +  4, LE);

        my $num-locals                :=     $bc.read-uint32($offset +  8, LE);
        my $num-lexicals              :=     $bc.read-uint32($offset + 12, LE);
        my $cuid                      := $st[$bc.read-uint32($offset + 16, LE)];
        my $name                      := $st[$bc.read-uint32($offset + 20, LE)];
        my $outer-index               :=     $bc.read-uint16($offset + 24, LE);
        my $annotation-offset         :=     $bc.read-uint32($offset + 26, LE);
        my $annotation-entries        :=     $bc.read-uint32($offset + 30, LE);
        my $num-handlers              :=     $bc.read-uint32($offset + 34, LE);
        my $flags                     :=     $bc.read-uint16($offset + 38, LE);
        my $num-static-lexical-values :=     $bc.read-uint16($offset + 40, LE);
        my $sc-dependency-index       :=     $bc.read-uint32($offset + 42, LE);
        my $sc-object-index           :=     $bc.read-uint32($offset + 46, LE);
        my $num-debug-names           :=     $bc.read-uint32($offset + 50, LE);
        $offset = $offset + 54;

        my str $filename;
        my $statements := IterationBuffer.new;
        if $annotation-entries {
            my uint32 $offset = $M.annotation-data-offset + $annotation-offset;
            $filename = $st[$bc.read-uint32($offset + 4, LE)];

            my int $last-bc-offset;
            for ^$annotation-entries {
                my int $bc-offset = $bc.read-uint32($offset, LE);
                if $bc-offset != $last-bc-offset {
                    $statements.push: MoarVM::Bytecode::Statement.new(
                      :offset($bc-offset),
                      :line($bc.read-uint32($offset + 8, LE))
                    );
                    $last-bc-offset = $bc-offset;
                }
                $offset = $offset + 12;
            }
        }

        my @locals;
        for ^$num-locals {
            @locals.push: {
              :type(@localtype[$bc.read-uint16($offset, LE)])
            };
            $offset = $offset + 2;
        }

        my @lexicals;
        for ^$num-lexicals {
            @lexicals.push: {
              :type(@localtype[$bc.read-uint16($offset,     LE)]),
              :name($st[       $bc.read-uint32($offset + 2, LE)]),
            };
            $offset = $offset + 6;
        }

        my $handlers := IterationBuffer.new;
        for ^$num-handlers {
            my $start-protected-region := $bc.read-uint32($offset,      LE);
            my $end-protected-region   := $bc.read-uint32($offset +  4, LE);
            my $category-mask          := $bc.read-uint32($offset +  8, LE);
            my $action                 := $bc.read-uint16($offset + 12, LE);
            my $register-with-block    := $bc.read-uint16($offset + 14, LE);
            my $handler-goto           := $bc.read-uint32($offset + 16, LE);
            $offset = $offset + 20;

            my $extra := 0;
            if $category-mask +& 4096 {
                $extra := $bc.read-uint16($offset, LE);
                $offset = $offset + 2;
            }

            $handlers.push: MoarVM::Bytecode::Handler.new(
              :$start-protected-region, :$end-protected-region, :$category-mask,
              :$action, :$register-with-block, :$handler-goto, :$extra
            );
        }

        for ^$num-static-lexical-values {
            my %lexical := @lexicals[$bc.read-uint16($offset, LE)];
            %lexical<flags>               := $bc.read-uint16($offset + 2, LE);
            %lexical<sc-dependency-index> := $bc.read-uint32($offset + 4, LE);
            %lexical<sc-object-index>     := $bc.read-uint32($offset + 8, LE);
            $offset = $offset + 12;
        }

        for ^$num-debug-names {
            my %local := @locals[$bc.read-uint16($offset,     LE)];
            %local<name> :=  $st[$bc.read-uint32($offset + 2, LE)];
            $offset = $offset + 6;
        }

        my @statements := $statements.List;
        my @handlers   := $handlers.List;

        @locals   := @locals.map(  {MoarVM::Bytecode::Local.new(  |$_)}).List;
        @lexicals := @lexicals.map({MoarVM::Bytecode::Lexical.new(|$_)}).List;

        my $opcodes  := { $bc.subbuf($opcodes-offset, $opcodes-length) }

        my $frame := MoarVM::Bytecode::Frame.new(
          :$M, :$index, :$opcodes,
          :$num-locals, :$num-lexicals, :$num-handlers,
          :$cuid, :$outer-index, :$flags,
          :$sc-dependency-index, :$sc-object-index,
          :@statements, :@handlers, :@locals, :@lexicals
        );

        $frame := $frame but MoarVM::Bytecode::Name(    $name    ) if $name;
        $frame := $frame but MoarVM::Bytecode::Filename($filename) if $filename;
        $frame
    }

    method gist(MoarVM::Bytecode::Frames:D:) {
        my str @parts = "Frames: $!elems frames, $!bytes bytes";
        @parts.push: format8d($!total-locals) ~ " local variables"
          if $!total-locals;
        @parts.push: format8d($!total-lexicals) ~ " lexical variables"
          if $!total-lexicals;
        @parts.push: format8d($!total-handlers) ~ " handlers"
          if $!total-handlers;
        @parts.push: format8d($!total-lexical-values) ~ " static lexical values"
          if $!total-lexical-values;
        @parts.push: format8d($!total-local-debug-names) ~ " local debug names"
          if $!total-local-debug-names;

        @parts.join("\n")
    }
}

#- MoarVM::Bytecode ------------------------------------------------------------
class MoarVM::Bytecode does Iterable {
    has str     $.path;
    has Buf     $.bytecode;
    has Strings $.strings         is built(False);
    has         @.sc-dependencies is built(False);
    has         @.extension-ops   is built(False);
    has Frames  $.frames          is built(False);
    has         @.callsites       is built(False);
    has         @.cu-dependencies is built(False);

    # Object setup
    multi method new(Str:D $path is copy) {
        my $io := $path.chars == 1
          ?? self.setting($path).IO
          !! $path.IO;

        if $io.e {
            self.new($io)
        }
        else {
            die "'$path' is not a valid path or identity";
        }
    }
    multi method new(IO:D $io) {
        self.new($io.slurp(:bin), :path($io.absolute))
    }
    multi method new(Blob:D $bytecode, :$path = "") {
        self.bless(:$bytecode, :$path)
    }

    method TWEAK() {
        my $bytecode := $!bytecode;

        # Search for the magic string.  In precompiled modules, the actual
        # MoarVM bytecode is prefixed with a number of lines of compunit
        # dependencies, followed by an empty line before the magic string
        my uint $offset = -1;
        my uint $max = IDMAX min $bytecode.elems - 8;
        Nil while ++$offset < $max && $bytecode.read-uint64($offset) != MAGIC;

        if $offset == $max {
            die Q|Magic string "MOARVM\r\n" not found|;
        }
        elsif $offset {
            @!cu-dependencies := self!make-cu-dependencies($offset);
            $!bytecode := $bytecode.subbuf($offset);
        }

        my $version := self.version;
        die Q|Unsupported bytecode version: expected 7 but got | ~ $version
          unless $version == 7;

        $!strings         := Strings.new(self);
        @!sc-dependencies := self!make-sc-dependencies;
        @!extension-ops   := self!make-extension-ops;
        $!frames          := Frames.new(self);
        @!callsites       := self!make-callsites;
    }

    # Helper methods for creating object, mostly for readability
    method !make-cu-dependencies(uint $offset) {
        $!bytecode.subbuf(0, $offset).decode.lines.head(*-1).map({
            CompUnit::PrecompilationDependency::File.deserialize($_)
        }).List
    }

    method !make-sc-dependencies() {
        my $bytecode        := $!bytecode;
        my $strings         := $!strings;
        my $sc-dependencies := IterationBuffer.new;

        my uint $offset = self.sc-dependencies-offset;
        my uint $last   = $offset + (self.sc-dependencies-entries * 4);
        while $offset < $last {
            $sc-dependencies.push:
              $strings[$bytecode.read-uint32($offset, LE)];
            $offset = $offset + 4;
        }
        $sc-dependencies.List
    }

    method !make-extension-ops() {
        my $bytecode      := $!bytecode;
        my $strings       := $!strings;
        my $extension-ops := IterationBuffer.new;

        my $offset     = self.extension-ops-offset;
        my $last       = $offset + (self.extension-ops-entries * 12);
        my uint $index = EXTOPS;
        while $offset < $last {
            my $name       := $strings[$bytecode.read-uint32($offset, LE)];
            my $descriptor := $bytecode.subbuf($offset + 4, 8);
            my $bytes := 2 + 2 * $descriptor.grep(* > 0).elems;

            $extension-ops.push: ExtensionOp.new(
              :$name, :$index, :$bytes, :$descriptor
            );
            $offset = $offset + 12;
            ++$index;
        }
        $extension-ops.List
    }

    method !make-callsites() {
        my $bytecode  := $!bytecode;
        my $strings   := $!strings;
        my $callsites := IterationBuffer.new;

        my uint $offset  = self.callsites-data-offset;
        my uint $entries = self.callsites-data-entries;
        for ^$entries {
            my @arguments;
            my @named;
            my %named;

            my $num-args := $bytecode.read-uint16($offset, LE) +& 0x0ff;
            $offset = $offset + 2;

            for ^$num-args {
                my uint8 $flags = $bytecode.read-uint8($offset++);
                @arguments.push: Argument.new($flags);
                @named.push($_)
                  if  $flags +& MVM_CALLSITE_ARG_NAMED
                  && !($flags +& MVM_CALLSITE_ARG_FLAT);
            }

            ++$offset if $num-args +& 1;  # padding to 16bit boundary

            for @named {
                my str $name = $strings[$bytecode.read-uint32($offset, LE)];
                %named{$name} := @arguments[$_]
                              := @arguments[$_] but Name($name);
                $offset = $offset + 4;
            }

            my $bytes := 2 * $num-args;

            $callsites.push: Callsite.new(
              :@arguments, :$bytes, :named(%named ?? %named.Map !! NONAMED)
            );
        }
        $callsites.List
    }

    # Other basic accessors
    method version()  { self.uint32(8) }
    method hll-name() { self.str(76)   }

    method sc-dependencies-offset()  { self.uint32(12) }
    method sc-dependencies-entries() { self.uint32(16) }
    method extension-ops-offset()    { self.uint32(20) }
    method extension-ops-entries()   { self.uint32(24) }
    method frames-data-offset()      { self.uint32(28) }
    method frames-data-entries()     { self.uint32(32) }
    method callsites-data-offset()   { self.uint32(36) }
    method callsites-data-entries()  { self.uint32(40) }
    method string-heap-offset()      { self.uint32(44) }
    method string-heap-entries()     { self.uint32(48) }
    method sc-data-offset()          { self.uint32(52) }
    method sc-data-length()          { self.uint32(56) }
    method opcodes-offset()          { self.uint32(60) }
    method opcodes-length()          { self.uint32(64) }
    method annotation-data-offset()  { self.uint32(68) }
    method annotation-data-length()  { self.uint32(72) }

    method main-entry-frame-index()      { self.uint32(80) }
    method library-load-frame-index()    { self.uint32(84) }
    method deserialization-frame-index() { self.uint32(88) }

    method coverables() {
        # +4 = skip bytecode entry on initialization
        my int $offset = self.annotation-data-offset + 4;
        my $entries   := self.annotation-data-length / 12;
        my $bytecode  := $!bytecode;
        my $strings   := $!strings;
        my %annotations;

        # Run through the all of the annotations
        for ^$entries {
            my $file := $strings[$bytecode.read-uint32($offset, LE)];
            (%annotations{$file} //= my int @).push(
              $bytecode.read-uint32($offset + 4, LE)
            ) unless $file.starts-with("EVAL_");
            $offset = $offset + 12;
        }

        # Remove all of the dupes
        $_ = .sort.squish for %annotations.values;

        %annotations.Map
    }

    # Introspection methods
    multi method op(Int:D $index) {
        MoarVM::Op.new($index)
          // $index >= EXTOPS && @!extension-ops[$index - EXTOPS]
          // "No op known at index $index".Failure
    }
    multi method op(Str:D $name) {
        MoarVM::Op.new($name)
          // @!extension-ops.first(*.name eq $name)
          // "No op known with name '$name'".Failure
    }

    method iterator() { MoarVM::Bytecode::Iterator.new(:source(self)) }

    method de-compile(:$verbose) {
        self.hyper(:batch(1024)).map(*.gist(:$verbose)).join("\n")
    }

    # Utility methods
    method uint16(uint $offset) { $!bytecode.read-uint16($offset, LE) }
    method uint16s(uint $offset is copy, uint $entries = 16) {
        my $bytecode := $!bytecode;
        my uint16 @values;
        for ^$entries {
            @values.push: $bytecode.read-uint16($offset, LE);
            $offset = $offset + 2;
        }
        @values
    }

    method uint32(uint $offset) { $!bytecode.read-uint32($offset, LE) }
    method uint32s(uint $offset is copy, uint $entries = 16) {
        my $bytecode := $!bytecode;
        my uint32 @values;
        for ^$entries {
            @values.push: $bytecode.read-uint32($offset, LE);
            $offset = $offset + 4;
        }
        @values
    }

    method str(uint $offset) {
        $!strings[$!bytecode.read-uint32($offset, LE)]
    }

    method slice(uint $offset, uint $bytes = 256) {
        $!bytecode[$offset ..^ $offset + $bytes]
    }

    method subbuf(
      uint $offset,
      uint $bytes = $!bytecode.elems - $offset
    ) {
        $!bytecode.subbuf($offset, $bytes)
    }

    method opcodes() {
        $!bytecode.subbuf(self.opcodes-offset, self.opcodes-length)
    }

    multi method hexdump(Int:D $offset, Int:D $bytes = 256) {
        dumphex($!bytecode, $offset, $bytes)
    }
    multi method hexdump(
      Buf:D $bytecode, Int:D $offset = 0; Int:D $bytes = 256
    ) {
        dumphex($bytecode, $offset, $bytes)
    }

    method rootdir() { $*EXECUTABLE.parent(3) }

    method setting(str $version = "c") {
        my $filename = "CORE.$version.setting.moarvm";
        paths(self.rootdir, :file(* eq $filename)).sort.head
    }

    method files(:$instantiate) {
        my @paths = paths(self.rootdir, :file(*.ends-with(".moarvm"))).sort;
        $instantiate
          ?? @paths.map({ self.new($_) })
          !! @paths
    }

    multi method gist(MoarVM::Bytecode:D:) {
        my str @parts = $!path ?? "File: $!path" !! "Created from a Blob";
        @parts.push: "Size: $!bytecode.elems() bytes";

        @parts.push: "Opcodes: " ~ self.opcodes-length ~ " bytes";
        @parts.push: $!strings.gist;
        @parts.push: $!frames.gist;
        if @!callsites.elems -> $elems {
            @parts.push: "Call sites: $elems";
        }

        if @!extension-ops -> @ops {
            @parts.push: "Extension Ops: @ops.elems()";
            @parts.push: "  $_.gist()" for @ops;
        }
        else {
            @parts.push: "Extension Ops: none";
        }

        if @!sc-dependencies -> @deps {
            @parts.push: "Serialization context dependencies: @deps.elems()";
            @parts.push: "  $_" for @deps;
        }
        else {
            @parts.push: "Serialization context dependencies: none";
        }

        if self.coverables.sort(*.key) -> @coverables {
            my $entries := self.annotation-data-length / 12;
            my $lines   := @coverables.map(*.value.elems).sum;
            @parts.push: "Coverable keys: @coverables.elems() from $lines lines ($entries annotations)";
            @parts.push: "  $_.key(): $_.value.elems()"
              for @coverables;
        }

        @parts.join("\n")
    }
}

#- setting ^ver ^auth ^api -----------------------------------------------------

use META::verauthapi:ver<0.0.1+>:auth<zef:lizmat> $?DISTRIBUTION,
  MoarVM::Bytecode,
  MoarVM::Op,
;

# vim: expandtab shiftwidth=4
