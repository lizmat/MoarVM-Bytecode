[![Actions Status](https://github.com/lizmat/MoarVM-Bytecode/actions/workflows/test.yml/badge.svg)](https://github.com/lizmat/MoarVM-Bytecode/actions)

NAME
====

MoarVM::Bytecode - Provide introspection into MoarVM bytecode

SYNOPSIS
========

```raku
use MoarVM::Bytecode;

my $M = MoarVM::Bytecode.new($filename);  # or letter or IO or Blob

say $M.hll-name;     # most likely "Raku"

say $M.strings[99];  # the 100th string on the string heap
```

DESCRIPTION
===========

MoarVM::Bytecode provides an object oriented interface to the MoarVM bytecode format, based on the information provided in [docs/bytecode.markdown](https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode).

CLASS METHODS
=============

new
---

```raku
my $M = MoarVM::Bytecode.new("c");           # the 6.c setting

my $M = MoarVM::Bytecode.new("foo/bar");     # file as string

my $M = MoarVM::Bytecode.new($filename.IO);  # path as IO object

my $M = MoarVM::Bytecode.new($buf);          # a Buf object
```

Create an instance of the `MoarVM::Bytecode` object from a letter (assumed to be a Raku version letter such as "c", "d" or "e"), a filename, an `IO::Path` or a `Buf`/`Blob` object.

files
-----

```raku
.say for MoarVM::Bytecode.files;
```

Returns a sorted list of paths of MoarVM bytecode files that could be found in the installation of the currently running `rakudo` executable.

root
----

```raku
my $rootdir = MoarVM::Bytecode.rootdir;
```

Returns an `IO::Path` of the root directory of the installation of the currently running `rakudo` executable.

setting
-------

```raku
my $setting = MoarVM::Bytecode.setting;

my $setting = MoarVM::Bytecode.setting("d");
```

Returns an `IO::Path` of the bytecode file of the given setting letter. Assumes the currently lowest supported setting by default.

INSTANCE METHODS
================

hexdump
-------

```raku
say $M.hexdump($M.string-heap-offset);  # defaults to 256

say $M.hexdump($M.string-heap-offset, 1024);
```

Returns a hexdump representation of the bytecode from the given byte offset for the given number of bytes (256 by default).

hll-name
--------

```raku
say $M.hll-name;     # most likely "Raku"
```

Returns the HLL language name for this bytecode. Most likely "Raku", or "nqp".

sc-dependencies
---------------

```raku
.say for $M.sc-dependencies;  # identifiers for Serialization Context
```

Returns an object that serves as a `Positional` for all of the strings of the Serialization Contexts on which this bytecode depends.

strings
-------

```raku
.say for $M.strings[^10];  # The first 10 strings on the string heap
```

Returns an object that serves as a `Positional` for all of the strings on the string heap.

version
-------

```raku
say $M.version;     # most likely 7
```

Returns the numeric version of this bytecode. Most likely "7".

PRIMITIVES
==========

bytecode
--------

```raku
my $b = $M.bytecode;
```

Returns the `Buf` with the bytecode.

slice
-----

```raku
dd $M.slice(0, 8).chrs;     # "MOARVM\r\n"
```

Returns a `List` of unsigned 32-bit integers from the given offset and number of bytes. Basically a shortcut for `$M,bytecode[$offset ..^ $offset + $bytes]`. The number of bytes defaults to `256` if not specified.

subbuf
------

```raku
dd $M.subbuf(0, 8).decode;  # "MOARVM\r\n"
```

Calls `subbuf` on the `bytecode` and returns the result. Basically a shortcut for `$M.bytecode.subbuf(...)`.

uint32
------

```raku
my $i = $M.uint32($M.string-heap-offset);
```

Returns the unsigned 32-bit integer value at the given offset in the bytecode.

HEADER SHORTCUTS
================

The following methods provide shortcuts to the values in the bytecode header. They are explained in the [MoarVM documentation](https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode).

`sc-dependencies-offset`, `sc-dependencies-entries`, `extension-ops-offset`, `extension-ops-entries`, `frames-data-offset`, `frames-data-entries`, `callsites-data-offset`, `callsites-data-entries`, `string-heap-offset`, `string-heap-entries`, `sc-data-offset`, `sc-data-length`, `bytecode-offset`, `bytecode-length`, `annotation-offset`, `annotation-length`, `main-entry-frame-index`, `library-load-frame-index`, `deserialization-frame-index`

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

COPYRIGHT AND LICENSE
=====================

Copyright 2024 Elizabeth Mattijsen

Source can be located at: https://github.com/lizmat/MoarVM-Bytecode . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

