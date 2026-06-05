# lispfs

[![CI](https://github.com/lispnik/lispfs/actions/workflows/ci.yml/badge.svg)](https://github.com/lispnik/lispfs/actions/workflows/ci.yml)

A **FUSE filesystem implemented in Common Lisp**, where every filesystem
operation on the mount is a Lisp closure.

It fills a `struct fuse_operations` (a table of ~15 function pointers) with
closures created by
[cffi-callback-closures](https://github.com/lispnik/cffi-callback-closures),
so when you `ls`, `cat`,
`echo >`, `mkdir`, or `rm` on the mountpoint, the kernel calls **into Lisp** for
every syscall. It's the FUSE "table of cooperating callbacks driving real OS
behavior" pattern.

## What you get (the hybrid backend)

One mount with three subtrees:

```
/mem      a real read/write in-memory filesystem (ramfs)
/lisp     a live view of the running image  (+ an eval REPL)
/compute  files that are pure functions of their path
```

Verified live:

```sh
$ ls /tmp/lispfs
compute  lisp  mem

# /compute — the path IS the program
$ cat /tmp/lispfs/compute/fib/30
832040
$ cat /tmp/lispfs/compute/primes/30
2 3 5 7 11 13 17 19 23 29
$ cat /tmp/lispfs/compute/reverse/hello
olleh

# /lisp — browse the running Lisp; eval through the filesystem
$ cat /tmp/lispfs/lisp/room
Dynamic space usage: 66,029,648 bytes
Bytes consed:        430,040,608
$ echo '(loop for i below 5 collect (* i i))' > /tmp/lispfs/lisp/eval
$ cat /tmp/lispfs/lisp/eval
(0 1 4 9 16)

# /mem — a genuine read/write filesystem
$ echo "hello fuse" > /tmp/lispfs/mem/note.txt
$ echo "second line" >> /tmp/lispfs/mem/note.txt
$ cat /tmp/lispfs/mem/note.txt
hello fuse
second line
$ mkdir /tmp/lispfs/mem/sub && mv /tmp/lispfs/mem/note.txt /tmp/lispfs/mem/sub/
```

## Architecture

- **`src/` — the VFS core (pure Lisp, no FUSE).** A `probe`/mutator protocol;
  a `router` that dispatches by the first path component to a sub-backend; and
  the three backends (`mem`, `lisp-backend`, `compute`). Fully unit-tested
  in-process — no mount required:

  ```lisp
  (asdf:test-system :lispfs)
  ```

- **`fuse/` — the FUSE binding.** `grovel.lisp` reads the real macFUSE headers
  for `struct fuse_operations`'s size, `struct stat`'s field offsets, and the
  errno/mode constants. `fuse.lisp` defines each operation as a libffi closure
  that translates the C call to/from the VFS protocol, then fills the struct
  and calls `fuse_main_real`. Each op is wrapped so a Lisp error returns `-EIO`
  rather than crashing the mount. This is the `lispfs-fuse` system (in
  `lispfs-fuse.asd`), kept separate from the core so loading `lispfs.asd`
  pulls in no FFI dependencies.

## Requirements

The FUSE layer is cross-platform (FUSE 2.9 high-level API). Verified on:

- **macOS** — macFUSE (`brew install --cask macfuse`; a kernel extension —
  needs admin, a reboot, and a one-time security approval in System Settings).
- **Linux** — `libfuse-dev` (FUSE 2.9) + `libffi-dev` + a C compiler.
  Verified on Debian 13 / aarch64 (Raspberry Pi 4), SBCL 2.5.2.

Plus `cffi`, `cffi-grovel`, `cffi-libffi`, and the sibling
`cffi-callback-closures`.

> **Portability note:** the struct field widths (`mode_t`, `off_t`, `size_t`,
> …) are *groveled* from the system headers (`fuse/grovel.lisp`), so they are
> correct on every platform — that's what makes one codebase serve both
> macFUSE and Linux libfuse.
>
> On non-x86 Linux, use upstream `cffi`/`cffi-libffi` rather than Debian's
> `cl-cffi`: the latter's `cffi-libffi` grovel references the x86-only
> `FFI_UNIX64` and fails to compile on aarch64.

## Running

The core builds anywhere. The mount needs FUSE and a source registry that finds
`cffi-callback-closures` (and, on aarch64, an upstream `cffi`):

```sh
cd lispfs
LISPFS_REGISTRY=/path/to/checkouts \
  sbcl --load fuse/mount.lisp --end-toplevel-options /tmp/lispfs   # blocks
# ... in another shell, poke at /tmp/lispfs ...

umount /tmp/lispfs          # macOS
fusermount -u /tmp/lispfs   # Linux
```

(`LISPFS_REGISTRY` is the directory tree ASDF should scan; defaults to
`~/Projects/common-lisp/`.)

## Notes

- Mounted single-threaded + foreground (`-s -f`), so the op closures run on the
  thread that called `mount` — a real Lisp thread, which keeps GC/threading
  simple.
- **I/O is bulk-copied.** `read`/`write` move data with `memcpy` (via
  `cffi:with-pointer-to-vector-data`), not byte-by-byte, and the `mem` backend
  uses a doubling capacity buffer so sequential writes are amortized O(1).
  Measured on a Pi 4: ~42 MB/s write, ~217 MB/s read for a 32 MB file (the
  earlier naive versions were ~0.2 MB/s and crawled). `probe` returns the
  logical size alongside the (possibly larger) buffer so readers never see past
  end-of-file.
- `getattr` reports the mounting user as owner so writes are permitted (works
  on both macOS and Linux).
- macOS sprinkles `._*` AppleDouble metadata files into writable dirs; that's
  the OS, not us. Linux doesn't.

## License

MIT.