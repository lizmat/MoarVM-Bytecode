# An attempt at providing introspection into the MoarVM bytecode format

use List::Agnostic:ver<0.0.1>:auth<zef:lizmat>;
use paths:ver<10.0.9>:auth<zef:lizmat>;

my constant @localtype = <
  0      int8 int16 int32 int64 num32 num64 str    obj    9
  10     11   12    13    14    15    16    uint8  uint16 uint32
  uint64
>;
my constant LE = LittleEndian;

# From src/core/callsite.h
my constant MVM_CALLSITE_ARG_OBJ     =   1; # object
my constant MVM_CALLSITE_ARG_INT     =   2; # native integer, signed
my constant MVM_CALLSITE_ARG_NUM     =   4; # native floating point number
my constant MVM_CALLSITE_ARG_STR     =   8; # native NFG string (MVMString REPR)
my constant MVM_CALLSITE_ARG_LITERAL =  16; # literal
my constant MVM_CALLSITE_ARG_NAMED   =  32; # named argument
my constant MVM_CALLSITE_ARG_FLAT    =  64; # flattened argument
my constant MVM_CALLSITE_ARG_UINT    = 128; # native integer, unsigned

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
    has @.arguments;
}

#- MoarVM::Bytecode::ExtensionOp -----------------------------------------------
my class MoarVM::Bytecode::ExtensionOp {
    has str $.name;
    has Buf $.descriptor;

    multi method gist(MoarVM::Bytecode::ExtensionOp:D:) {
        "$!name.fmt('%-16s') ($!descriptor.gist.substr(14, *-1))"
    }
}

#- MoarVM::Bytecode::Frame -----------------------------------------------------
my class MoarVM::Bytecode::Frame {
    has uint32 $.index;
    has uint32 $.bytecode-offset;
    has uint32 $.bytecode-length;
    has str    $.cuuid;
    has uint16 $.outer-index;
    has uint16 $.flags;
    has uint32 $.sc-dependency-index;
    has uint32 $.sc-object-index;
    has        @.statements;
    has        @.locals;
    has        @.lexicals;
    has        @.handlers;

    method name(    --> "") { }
    method filename(--> "") { }

    method no-outer()         { $!outer-index == $!index }
    method has-exit-handler() { $!flags +& 1             }
    method is-thunk()         { $!flags +& 2 && 1        }

    multi method gist(MoarVM::Bytecode::Frame:D:) {
        my str @parts = $!cuuid.fmt("%4d");

        if self.filename -> $filename is copy {
            $filename = $filename.split("/").tail;
            @parts.push: @!statements
              ?? "$filename:@!statements.head.line()"
              !! $filename;

            if self.name -> $name {
                @parts.push: qq/"$name"/;
            }
        }

        @parts.push: "no-outer"         if self.no-outer;
        @parts.push: "has-exit-handler" if self.has-exit-handler;
        @parts.push: "is-thunk"         if self.is-thunk;

        @parts.push: "(@!statements.elems() stmts, $!bytecode-length bytes)";

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

    my int @extra = 4, 7, 6, 5;

    method new($M) {
        my uint32 @offsets;

        my int $offset = $M.string-heap-offset;
        my int $elems  = $M.string-heap-entries;
        my int $i;
        while $i < $elems {
            @offsets.push: $offset;

            my int $bytes = $M.uint32($offset) +> 1;
            $offset = $offset + $bytes + @extra[$bytes +& 0x03];
            ++$i;
        }

        self.bless(:$M, :@offsets, :$elems)
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

    method gist(MoarVM::Bytecode::Strings:D:) {
        "String Heap: $!elems different strings"
    }
}

#- MoarVM::Bytecode::Frames ----------------------------------------------------
# Encapsulate the frames heap as a Positional
my class MoarVM::Bytecode::Frames does List::Agnostic {
    has      $!M      is built;
    has      @!frames is built;
    has uint $.elems;
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

        my int $offset = $M.frames-data-offset;
        my int $elems  = $M.frames-data-entries;
        my int $i;
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
          :$M, :@frames, :$elems, :$total-locals, :$total-lexicals,
          :$total-handlers, :$total-lexical-values, :$total-local-debug-names
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

        my $bytecode-offset           :=     $bc.read-uint32($offset,      LE);
        my $bytecode-length           :=     $bc.read-uint32($offset +  4, LE);
        my $num-locals                :=     $bc.read-uint32($offset +  8, LE);
        my $num-lexicals              :=     $bc.read-uint32($offset + 12, LE);
        my $cuuid                     := $st[$bc.read-uint32($offset + 16, LE)];
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

        my $frame := MoarVM::Bytecode::Frame.new(
          :$index, :$bytecode-offset, :$bytecode-length, :$num-locals,
          :$num-lexicals, :$cuuid, :$outer-index, :$num-handlers,
          :$flags, :$sc-dependency-index, :$sc-object-index,
          :@statements, :@handlers, :@locals, :@lexicals
        );

        $frame := $frame but MoarVM::Bytecode::Name(    $name    ) if $name;
        $frame := $frame but MoarVM::Bytecode::Filename($filename) if $filename;
        $frame
    }

    method gist(MoarVM::Bytecode::Frames:D:) {
        my str @parts = "Frames: $!elems";
        @parts.push: "$!total-locals.fmt('%8d') local variables"
          if $!total-locals;
        @parts.push: "$!total-lexicals.fmt('%8d') lexical variables"
          if $!total-lexicals;
        @parts.push: "$!total-handlers.fmt('%8d') handlers"
          if $!total-handlers;
        @parts.push: "$!total-lexical-values.fmt('%8d') static lexical values"
          if $!total-lexical-values;
        @parts.push: "$!total-local-debug-names.fmt('%8d') local debug names"
          if $!total-local-debug-names;

        @parts.join("\n")
    }
}

#- MoarVM::Bytecode ------------------------------------------------------------
class MoarVM::Bytecode {
    has str     $.path;
    has Buf     $.bytecode;
    has Strings $.strings         is built(False);
    has         @.sc-dependencies is built(False);
    has         @.extension-ops   is built(False);
    has Frames  $.frames          is built(False);
    has         @.callsites       is built(False);

    # Object setup
    multi method new(Str:D $path is copy) {
        $path = self.setting($path) if $path.chars == 1;
        self.new($path.IO )
    }
    multi method new(IO:D $io) {
        self.new($io.slurp(:bin), :path($io.absolute))
    }
    multi method new(Blob:D $bytecode, :$path = "") {
        self.bless(:$bytecode, :$path)
    }

    method TWEAK() {
        my $bytecode := $!bytecode;

        my $magic := $bytecode[^8].chrs;
        die Q|Unsupported magic string: expected "MOARVM\r\n" but got | ~ $magic
          unless $magic eq "MOARVM\r\n";

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

        my $offset = self.extension-ops-offset;
        my $last   = $offset + (self.extension-ops-entries * 12);
        while $offset < $last {
            $extension-ops.push: ExtensionOp.new(
              :name($strings[$bytecode.read-uint32($offset, LE)]),
              :descriptor($bytecode.subbuf($offset + 4, 8))
            );
            $offset = $offset + 12;
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
            my @nameds;

            my $num-args := $bytecode.read-uint16($offset, LE) +& 0x0ff;
            $offset = $offset + 2;

            for ^$num-args {
                my uint8 $flags = $bytecode.read-uint8($offset++);
                @arguments.push: Argument.new($flags);
                @nameds.push($_) if $flags +& MVM_CALLSITE_ARG_NAMED;
            }

            ++$offset if $num-args +& 1;  # padding to 16bit boundary

            for @nameds {
                @arguments[$_] := @arguments[$_]
                  but Name($strings[$bytecode.read-uint32($offset, LE)]);
                $offset = $offset + 4;
            }

            $callsites.push: Callsite.new(:@arguments);
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
    method bytecode-offset()         { self.uint32(60) }
    method bytecode-length()         { self.uint32(64) }
    method annotation-data-offset()  { self.uint32(68) }
    method annotation-data-length()  { self.uint32(72) }

    method main-entry-frame-index()      { self.uint32(80) }
    method library-load-frame-index()    { self.uint32(84) }
    method deserialization-frame-index() { self.uint32(88) }

    # Utility methods
    method uint16(uint $offset) {
        $!bytecode.read-uint16($offset, LittleEndian)
    }
    method uint16s(uint $offset is copy, uint $entries = 16) {
        my $bytecode := $!bytecode;
        my uint16 @values;
        for ^$entries {
            @values.push: $bytecode.read-uint16($offset, LittleEndian);
            $offset = $offset + 2;
        }
        @values
    }

    method uint32(uint $offset) {
        $!bytecode.read-uint32($offset, LittleEndian)
    }
    method uint32s(uint $offset is copy, uint $entries = 16) {
        my $bytecode := $!bytecode;
        my uint32 @values;
        for ^$entries {
            @values.push: $bytecode.read-uint32($offset, LittleEndian);
            $offset = $offset + 4;
        }
        @values
    }

    method str(uint $offset) {
        $!strings[$!bytecode.read-uint32($offset, LittleEndian)]
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

    method hexdump(uint $offset, uint $bytes = 256) {
        use HexDump::Tiny:ver<0.6>:auth<zef:raku-community-modules>;
        hexdump(
          $!bytecode.subbuf(
            $offset +& 0x0fffffff0,
            $bytes,
            :skip(16 - ($offset +& 0x0f))
          )
        ).join("\n")
    }

    method rootdir() { $*EXECUTABLE.parent(3) }

    method setting(str $version = "c") {
        my $filename = "CORE.$version.setting.moarvm";
        paths(self.rootdir, :file(* eq $filename)).sort.head
    }

    method files() {
        paths(self.rootdir, :file(*.ends-with(".moarvm"))).sort
    }

    multi method gist(MoarVM::Bytecode:D:) {
        my str $head  = $!path ?? "File: $!path" !! "Created from a Blob";
        my str @parts = "$head ($!bytecode.elems() bytes)";

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

        @parts.join("\n")
    }
}

# vim: expandtab shiftwidth=4
