# An attempt at providing introspection into the MoarVM bytecode format

use List::Agnostic:ver<0.0.1>:auth<zef:lizmat>;
use paths:ver<10.0.9>:auth<zef:lizmat>;

my constant @localtype = <
  0      int8 int16 int32 int64 num32 num64 str    obj    9
  10     11   12    13    14    15    16    uint8  uint16 uint32
  uint64
>;

#- MoarVM::Bytecode::ExtensionOp -----------------------------------------------
my class MoarVM::Bytecode::ExtensionOp {
    has str $.name;
    has Buf $.descriptor;
}

#- MoarVM::Bytecode::Frame -----------------------------------------------------
my class MoarVM::Bytecode::Frame {
    has uint32 $!offset;
    has str    $.compilation-unit;
    has str    $.name;
    has uint32 $.bytecode-offset;
    has uint32 $.bytecode-length;
    has uint16 $.outer-index;
    has uint32 $.annnotation-offset;
    has uint32 $.annnotation-entries;
    has uint32 $.handler-entries;
    has uint16 $.frame-flags;
    has uint16 $.static-lexical-values-entries;
    has uint32 $.sc-dependency-index;
    has uint32 $.sc-object-index;
    has uint32 $.debug-name-entries;
    has        @.locals;
    has        @.lexicals;
}

#- MoarVM::Bytecode::Handler --------------------------------------------
my class MoarVM::Bytecode::Handler {
    has uint32 $.start-protected-region;
    has uint32 $.end-protected-region;
    has uint32 $.category-mask;
    has uint16 $.action;
    has uint16 $.register-with-block;
    has uint32 $.handler-goto;
}

#- MoarVM::Bytecode::Strings ---------------------------------------------------
# Encapsulate the string heap as a Positional
my class MoarVM::Bytecode::Strings does List::Agnostic {
    has        $!M       is built;
    has uint32 @!offsets is built;
    has int    $.elems;

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
}

#- MoarVM::Bytecode ------------------------------------------------------------
class MoarVM::Bytecode {
    has Buf     $.bytecode;
    has Strings $.strings         is built(False);
    has         @.sc-dependencies is built(False);
    has         @.extension-ops   is built(False);

    # Object setup
    multi method new(Str:D $path) {
        self.new($path.chars == 1 ?? self.setting($path) !! $path.IO )
    }
    multi method new(IO:D $io) {
        self.new($io.slurp(:bin))
    }
    multi method new(Blob:D $bytecode) {
        self.bless(:$bytecode)
    }

    method TWEAK() {
        my $bytecode := $!bytecode;

        my $magic := $bytecode[^8].chrs;
        die Q|Unsupported magic string: expected "MOARVM\r\n" but got | ~ $magic
          unless $magic eq "MOARVM\r\n";

        my $version := self.version;
        die Q|Unsupported bytecode version: expected 7 but got | ~ $version
          unless $version == 7;

        my $strings := Strings.new(self);

        my $sc-dependencies := IterationBuffer.new;
        my int $offset = self.sc-dependencies-offset;
        my int $last   = $offset + (self.sc-dependencies-entries * 4);
        while $offset < $last {
            $sc-dependencies.push: $strings[self.uint32($offset)];
            $offset += 4;
        }

        my $extension-ops := IterationBuffer.new;
        $offset = self.extension-ops-offset;
        $last   = $offset + (self.extension-ops-entries * 12);
        while $offset < $last {
            $extension-ops.push: ExtensionOp.new(
              :name($strings[self.uint32($offset)]),
              :descriptor($bytecode.subbuf($offset + 4, 8))
            );
            $offset += 12;
        }

        $!strings         := $strings;
        @!sc-dependencies := $sc-dependencies.List;
        @!extension-ops   := $extension-ops.List;
    }

    # Other basic accessors
    method version()  {           self.uint32( 8)  }
    method hll-name() { $!strings[self.uint32(76)] }

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
    method annotation-offset()       { self.uint32(68) }
    method annotation-length()       { self.uint32(72) }

    method main-entry-frame-index()      { self.uint32(80) }
    method library-load-frame-index()    { self.uint32(84) }
    method deserialization-frame-index() { self.uint32(88) }

    # Utility methods
    method uint16(int $offset) { $!bytecode.read-uint16($offset, LittleEndian) }
    method uint32(int $offset) { $!bytecode.read-uint32($offset, LittleEndian) }

    method slice(int $offset, int $bytes = 256) {
        $!bytecode[$offset ..^ $offset + $bytes]
    }

    method subbuf(
      int $offset,
      int $bytes = $!bytecode.elems - $offset
    ) {
        $!bytecode.subbuf($offset, $bytes)
    }

    method hexdump(int $offset, int $bytes = 256) {
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
}

# vim: expandtab shiftwidth=4
