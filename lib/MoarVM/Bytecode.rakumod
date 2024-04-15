# An attempt at providing introspection into the MoarVM bytecode format

use List::Agnostic:ver<0.0.1>:auth<zef:lizmat>;
use paths:ver<10.0.9>:auth<zef:lizmat>;

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

class MoarVM::Bytecode {
    has Buf     $.bytecode;
    has Strings $.strings  is built(False);

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
        my $magic := $!bytecode[^8].chrs;
        die Q|Unsupported magic string: expected "MOARVM\r\n" but got | ~ $magic
          unless $magic eq "MOARVM\r\n";

        my $version := self.version;
        die Q|Unsupported bytecode version: expected 7 but got | ~ $version
          unless $version == 7;

        $!strings := Strings.new(self);
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
    method uint32(int $offset) {
        $!bytecode.read-uint32($offset, LittleEndian)
    }

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

=begin pod

=head1 NAME

MoarVM::Bytecode - Provide introspection into MoarVM bytecode

=head1 SYNOPSIS

=begin code :lang<raku>

use MoarVM::Bytecode;

my $M = MoarVM::Bytecode.new($filename);  # or letter or IO or Blob

say $M.hll-name;     # most likely "Raku"

say $M.strings[99];  # the 100th string on the string heap

=end code

=head1 DESCRIPTION

MoarVM::Bytecode provides an object oriented interface to the MoarVM
bytecode format, based on the information provided in
L<docs/bytecode.markdown|https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode>.

=head1 CLASS METHODS

=head2 new

=begin code :lang<raku>

my $M = MoarVM::Bytecode.new("c");           # the 6.c setting

my $M = MoarVM::Bytecode.new("foo/bar");     # file as string

my $M = MoarVM::Bytecode.new($filename.IO);  # path as IO object

my $M = MoarVM::Bytecode.new($buf);          # a Buf object

=end code

Create an instance of the C<MoarVM::Bytecode> object from a letter (assumed
to be a Raku version letter such as "c", "d" or "e"), a filename, an
C<IO::Path> or a C<Buf>/C<Blob> object.

=head2 files

=begin code :lang<raku>

.say for MoarVM::Bytecode.files;

=end code

Returns a sorted list of paths of MoarVM bytecode files that could be found
in the installation of the currently running C<rakudo> executable.

=head2 root

=begin code :lang<raku>

my $rootdir = MoarVM::Bytecode.rootdir;

=end code

Returns an C<IO::Path> of the root directory of the installation of the
currently running C<rakudo> executable.

=head2 setting

=begin code :lang<raku>

my $setting = MoarVM::Bytecode.setting;

my $setting = MoarVM::Bytecode.setting("d");

=end code

Returns an C<IO::Path> of the bytecode file of the given setting letter.
Assumes the currently lowest supported setting by default.

=head1 INSTANCE METHODS

=head2 hexdump

=begin code :lang<raku>

say $M.hexdump($M.string-heap-offset);  # defaults to 256

say $M.hexdump($M.string-heap-offset, 1024);

=end code

Returns a hexdump representation of the bytecode from the given byte offset
for the given number of bytes (256 by default).

=head2 hll-name

=begin code :lang<raku>

say $M.hll-name;     # most likely "Raku"

=end code

Returns the HLL language name for this bytecode.  Most likely "Raku", or
"nqp".

=head2 strings

=begin code :lang<raku>

.say for $M.strings[^10];  # The first 10 strings on the string heap

=end code

Returns an object that serves as a C<Positional> for all of the strings on
the string heap.

=head2 version

=begin code :lang<raku>

say $M.version;     # most likely 7

=end code

Returns the numeric version of this bytecode.  Most likely "7".

=head1 PRIMITIVES

=head2 bytecode

=begin code :lang<raku>

my $b = $M.bytecode;

=end code

Returns the C<Buf> with the bytecode.

=head2 slice

=begin code :lang<raku>

dd $M.slice(0, 8).chrs;     # "MOARVM\r\n"

=end code

Returns a C<List> of unsigned 32-bit integers from the given offset and
number of bytes.  Basically a shortcut for
C<$M,bytecode[$offset ..^ $offset + $bytes]>.  The number of bytes defaults
to C<256> if not specified.

=head2 subbuf

=begin code :lang<raku>

dd $M.subbuf(0, 8).decode;  # "MOARVM\r\n"

=end code

Calls C<subbuf> on the C<bytecode> and returns the result.  Basically a
shortcut for C<$M.bytecode.subbuf(...)>.

=head2 uint32

=begin code :lang<raku>

my $i = $M.uint32($M.string-heap-offset);

=end code

Returns the unsigned 32-bit integer value at the given offset in the bytecode.

=head1 HEADER SHORTCUTS

The following methods provide shortcuts to the values in the bytecode header.
They are explained in the
L<MoarVM documentation|https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode>.

C<sc-dependencies-offset>, C<sc-dependencies-entries>,
C<extension-ops-offset>,   C<extension-ops-entries>,
C<frames-data-offset>,     C<frames-data-entries>,
C<callsites-data-offset>,  C<callsites-data-entries>,
C<string-heap-offset>,     C<string-heap-entries>,
C<sc-data-offset>,         C<sc-data-length>,
C<bytecode-offset>,        C<bytecode-length>,
C<annotation-offset>,      C<annotation-length>,
C<main-entry-frame-index>,
C<library-load-frame-index>,
C<deserialization-frame-index>

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

=head1 COPYRIGHT AND LICENSE

Copyright 2024 Elizabeth Mattijsen

Source can be located at: https://github.com/lizmat/MoarVM-Bytecode .
Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a
L<small sponsorship|https://github.com/sponsors/lizmat/>  would mean a great
deal to me!

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
