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

extension-ops
-------------

```raku
Returns a list of NQP extension operators that have been added to this
bytecode.  Each element consists of an L<ExtensionOp> object.
```

frames
------

```raku
.say for $M.frames[^10];  # The first 10 frames on the frame heap

my @frames := $M.frames.reify-all;
```

Returns a [Frames](Frames) object that serves as a `Positional` for all of the frames on the frame heap. Since the reification of a [Frame](#Frame) object is rather expensive, this is done lazily on each access.

To reify all `Frame` objects at once, one can call the `reify-all` method, which also returns a list of the reified `Frame` objects.

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

Returns a list of strings of the Serialization Contexts on which this bytecode depends.

strings
-------

```raku
.say for $M.strings[^10];  # The first 10 strings on the string heap
```

Returns a [Strings](Strings) object that serves as a `Positional` for all of the strings on the string heap.

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

hexdump
-------

```raku
say $M.hexdump($M.string-heap-offset);  # defaults to 256

say $M.hexdump($M.string-heap-offset, 1024);
```

Returns a hexdump representation of the bytecode from the given byte offset for the given number of bytes (256 by default).

slice
-----

```raku
dd $M.slice(0, 8).chrs;     # "MOARVM\r\n"
```

Returns a `List` of unsigned 32-bit integers from the given offset and number of bytes. Basically a shortcut for `$M,bytecode[$offset ..^ $offset + $bytes]`. The number of bytes defaults to `256` if not specified.

str
---

```raku
say $M.str(76);  # Raku or nqp
```

Returns the string of which the index is the given offset.

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

SUBCLASSES
==========

ExtensionOp
-----------

The `ExtensionOp` class provides these methods:

  * name

The name with which the extension op can be called

  * descriptor

An 8-byte `Buf` with descriptor information

Frame
-----

The `Frame` class provides these methods:

  * annotation-entries

A 32-bit unsigned integer offset for the number of annotations of this frame.

  * annotation-offset

A 32-bit unsigned integer offset in the annotations segment of the bytecode annotations of this frame.

  * bytecode-length

A 32-bit unsigned integer representing the number of bytes of bytecode of this frame.

  * bytecode-offset

A 32-bit unsigned integer offset in the bytecode segment of the bytecode of this frame.

  * cuuid

A string representing the compilation unit ID.

  * flags

A 16-bit unsigned integer bitmap with flags of this frame.

  * handlers

A list of [Handler](#Handler) objects, representing the handlers in this frame.

  * has-exit-handler

1 if this frame has an exit handler, otherwise 0.

  * index

A 16-bit unsigned integer indicating the frame index of this frame.

  * is-thunk

1 if this frame is a thunk (as opposed to a real scope), otherwise 0.

  * lexicals

A list of [Lexical](#Lexical) objects, representing the lexicals in this frame.

  * locals

A list of [Local](#Local) objects, representing the locals in this frame.

  * name

The name of this frame, if any.

  * no-outer

1 if this frame has no outer, otherwise 0.

  * outer-index

A 16-bit unsigned integer indicating the frame index of the outer frame.

  * sc-dependency-index

A 32-bit unsigned integer index into

  * sc-object-index

A 32-bit unsigned integer index into

Handler
-------

  * start-protected-region

  * end-protected-region

  * category-mask

  * action

  * register-with-block

  * handler-goto

Lexical
-------

  * name

The name of this lexical, if any.

  * type

The type of this lexical.

  * flags

A 16-bit unsigned integer bitmap for this lexical.

  * sc-dependency-index

Index of into the `sc-dependencies` list.

  * sc-object-index

Index of into the `sc-dependencies` list.

Local
-----

  * name

The name of this local, if any.

  * type

The type of this local.

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

COPYRIGHT AND LICENSE
=====================

Copyright 2024 Elizabeth Mattijsen

Source can be located at: https://github.com/lizmat/MoarVM-Bytecode . Comments and Pull Requests are welcome.

If you like this module, or what I’m doing more generally, committing to a [small sponsorship](https://github.com/sponsors/lizmat/) would mean a great deal to me!

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

