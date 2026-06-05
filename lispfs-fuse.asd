;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; lispfs-fuse.asd --- Mount a lispfs virtual filesystem via FUSE
;;;
;;; Kept in its own file (separate primary system name) so that loading the
;;; core lispfs.asd does not require cffi-grovel / cffi / cffi-callback-closures.
;;; Needs macFUSE (macOS) or libfuse 2.x (Linux).  See README.md.

(in-package :asdf)

(defsystem "lispfs-fuse"
  :description "Mount a lispfs virtual filesystem via FUSE; ops are Lisp closures."
  :author "Matthew Kennedy"
  :license "MIT"
  :defsystem-depends-on ("cffi-grovel")
  :depends-on ("lispfs" "cffi" "cffi-callback-closures")
  :components ((:module "fuse"
                :serial t
                :components ((:file "package")
                             (:cffi-grovel-file "grovel")
                             (:file "fuse")))))