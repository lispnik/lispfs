;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; lispfs.asd --- A FUSE filesystem implemented in Common Lisp
;;;
;;; Every filesystem operation on the mount is a Lisp closure, installed into a
;;; struct fuse_operations via cffi-callback-closures.  See README.md.

(in-package :asdf)

;;; NB: cffi-grovel is pulled in only by the lispfs/fuse system via
;;; :defsystem-depends-on, and its grovel component is referenced by the
;;; :cffi-grovel-file keyword class -- so loading this file (e.g. to build the
;;; dependency-free core) does not require cffi-grovel to be installed.

;;; Core: the virtual filesystem and its backends.  Pure Lisp, no FUSE -- so it
;;; can be developed and tested without a mount.
(defsystem "lispfs"
  :description "A virtual filesystem whose operations are Lisp closures."
  :author "Matthew Kennedy"
  :license "MIT"
  :depends-on ("uiop")
  :components ((:module "src"
                :serial t
                :components ((:file "packages")
                             (:file "vfs")
                             (:file "mem")
                             (:file "lisp-backend")
                             (:file "compute"))))
  :in-order-to ((test-op (test-op "lispfs/test"))))

;;; The FUSE binding: fills a struct fuse_operations with libffi closures and
;;; mounts.  Needs macFUSE (libfuse 2.x).  Kept separate so the core builds
;;; without it.
(defsystem "lispfs/fuse"
  :description "Mount a lispfs virtual filesystem via FUSE."
  :author "Matthew Kennedy"
  :license "MIT"
  :defsystem-depends-on ("cffi-grovel")
  :depends-on ("lispfs" "cffi" "cffi-callback-closures")
  :components ((:module "fuse"
                :serial t
                :components ((:file "package")
                             (:cffi-grovel-file "grovel")
                             (:file "fuse")))))

(defsystem "lispfs/test"
  :description "In-process tests for the lispfs core (no mount needed)."
  :depends-on ("lispfs")
  :components ((:module "tests"
                :serial t
                :components ((:file "tests"))))
  :perform (test-op (o c) (uiop:symbol-call :lispfs-test '#:run)))