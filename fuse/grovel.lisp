;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; grovel.lisp --- struct fuse_operations / struct stat layout + constants
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; We grovel the real header so member offsets and the full struct size are
;;; correct for the installed macFUSE.  We list only the operations we
;;; implement; grovel still reports the struct's true sizeof (passed to
;;; fuse_main_real and used to allocate a fully-sized, zeroed struct).

(in-package #:lispfs.fuse)

(define "FUSE_USE_VERSION" 29)
(pkg-config-cflags "fuse")          ; -I.../fuse -D_FILE_OFFSET_BITS=64

(include "fuse.h")
(include "sys/stat.h")
(include "errno.h")

(cstruct fuse-operations "struct fuse_operations"
  (getattr  "getattr"  :type :pointer)
  (mkdir    "mkdir"    :type :pointer)
  (unlink   "unlink"   :type :pointer)
  (rmdir    "rmdir"    :type :pointer)
  (rename   "rename"   :type :pointer)
  (truncate "truncate" :type :pointer)
  (open     "open"     :type :pointer)
  (read     "read"     :type :pointer)
  (write    "write"    :type :pointer)
  (readdir  "readdir"  :type :pointer)
  (create   "create"   :type :pointer)
  (utimens  "utimens"  :type :pointer))

;; Grovel the POSIX integer types so widths are correct on every platform
;; (e.g. mode_t/nlink_t are 16-bit on Darwin but 32/64-bit on Linux).  Offsets
;; come from the header regardless.
(ctype mode-t  "mode_t")
(ctype nlink-t "nlink_t")
(ctype uid-t   "uid_t")
(ctype gid-t   "gid_t")
(ctype off-t   "off_t")
(ctype size-t  "size_t")

(cstruct stat "struct stat"
  (mode  "st_mode"  :type mode-t)
  (nlink "st_nlink" :type nlink-t)
  (uid   "st_uid"   :type uid-t)
  (gid   "st_gid"   :type gid-t)
  (size  "st_size"  :type off-t))

(constant (+s-ifdir+ "S_IFDIR"))
(constant (+s-ifreg+ "S_IFREG"))

(constant (+eio+       "EIO"))
(constant (+enoent+    "ENOENT"))
(constant (+erofs+     "EROFS"))
(constant (+eexist+    "EEXIST"))
(constant (+enotempty+ "ENOTEMPTY"))
(constant (+eisdir+    "EISDIR"))
(constant (+enotdir+   "ENOTDIR"))
(constant (+eacces+    "EACCES"))