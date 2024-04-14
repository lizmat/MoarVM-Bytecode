[![Actions Status](https://github.com/lizmat/MoarVM-Bytecode/actions/workflows/test.yml/badge.svg)](https://github.com/lizmat/MoarVM-Bytecode/actions)

NAME
====

MoarVM::Bytecode - Provide introspection into MoarVM bytecode

SYNOPSIS
========

```raku
use MoarVM::Bytecode;

my $M = MoarVM::Bytecode.new($filename);  # or IO or Blob
```

DESCRIPTION
===========

MoarVM::Bytecode provides an object oriented interface to the MoarVM bytecode format, based on the information provided in [docs/bytecode.markdown](https://github.com/MoarVM/MoarVM/blob/main/docs/bytecode.markdown#bytecode).

AUTHOR
======

Elizabeth Mattijsen <liz@raku.rocks>

COPYRIGHT AND LICENSE
=====================

Copyright 2024 Elizabeth Mattijsen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

