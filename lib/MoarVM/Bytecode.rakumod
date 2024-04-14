# An attempt at providing introspection into the MoarVM bytecode format

use HexDump::Tiny;

class MoarVM::Bytecode {
    has $.bytecode;
    has uint32 $.sc_dependencies_offset is built(False);
    has uint32 $.extension_ops_offset   is built(False);
    has uint32 $.frames_data_offset     is built(False);
    has uint32 $.callsites_data_offset  is built(False);
    has uint32 $.string_heap_offset     is built(False);
    has uint32 $.sc_data_offset         is built(False);
    has uint32 $.bytecode_offset        is built(False);
    has uint32 $.annotation_offset      is built(False);

    # Object setup
    multi method new(Str:D $path) {
        self.bless(:bytecode($path.IO.slurp(:bin)))
    }
    multi method new(IO:D $io) {
        self.bless(:bytecode($io.slurp(:bin)))
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

        $!sc_dependencies_offset = self.uint32(12);
        $!extension_ops_offset   = self.uint32(20);
        $!frames_data_offset     = self.uint32(28);
        $!callsites_data_offset  = self.uint32(36);
        $!string_heap_offset     = self.uint32(44);
        $!sc_data_offset         = self.uint32(52);
        $!bytecode_offset        = self.uint32(60);
        $!annotation_offset      = self.uint32(68);
    }

    # Other basic accessors
    method version() { self.uint32(8) }

    method sc_dependencies_entries() { self.uint32(16) }
    method extension_ops_entries()   { self.uint32(24) }
    method frames_data_entries()     { self.uint32(32) }
    method callsites_data_entries()  { self.uint32(40) }
    method string_heap_entries()     { self.uint32(48) }
    method sc_data_length()          { self.uint32(56) }
    method bytecode_length()         { self.uint32(64) }
    method annotation_length()       { self.uint32(72) }

    method hll_name_offset() { self.uint32(76) }

    method main_entry_frame_index()      { self.uint32(80) }
    method library_load_frame_index()    { self.uint32(84) }
    method deserialization_frame_index() { self.uint32(88) }

    # Utility methods
    method uint32(int $offset) {
        $!bytecode.read-uint32($offset, LittleEndian)
    }
    method str(int $offset is copy) {
        $offset += $!string_heap_offset;

        my int $bytes = self.uint32($offset);
        my int $utf8  = $bytes +& 1;
        $bytes +>= 1;
        $offset += 4;

        $utf8
          ?? $!bytecode.subbuf($offset, $bytes).decode
          !! self.slice($offset, $bytes).chrs
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
        hexdump($!bytecode.subbuf($offset, $bytes)).join("\n")
    }
}

my $M := MoarVM::Bytecode.new("blib/CORE.c.setting.moarvm");
say $M.hexdump($M.string_heap_offset);
say $M.str($M.hll_name_offset);
say $M.hll_name_offset;



=begin pod

=head1 NAME

MoarVM::Bytecode - Provide introspection into MoarVM bytecode

=head1 SYNOPSIS

=begin code :lang<raku>

use MoarVM::Bytecode;

my $M = MoarVM::Bytecode.new($filename);  # or IO or Blob

=end code

=head1 DESCRIPTION

MoarVM::Bytecode provides an object oriented interface to the MoarVM
bytecode format, based on the information provided in
L<docs/bytecode.markdown|https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode>.

=head1 AUTHOR

Elizabeth Mattijsen <liz@raku.rocks>

=head1 COPYRIGHT AND LICENSE

Copyright 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
