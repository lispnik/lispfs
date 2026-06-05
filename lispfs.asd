;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; lispfs.asd --- A FUSE filesystem implemented in Common Lisp
;;;
;;; Every filesystem operation on the mount is a Lisp closure, installed into a
;;; struct fuse_operations via cffi-callback-closures.  See README.md.

(in-package :asdf)

;;; This file defines ONLY the dependency-free core (and its tests).  The FUSE
;;; binding lives in lispfs-fuse.asd so that merely loading this file does not
;;; drag in cffi-grovel / cffi / cffi-callback-closures.

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

(defsystem "lispfs/test"
  :description "In-process tests for the lispfs core (no mount needed)."
  :depends-on ("lispfs")
  :components ((:module "tests"
                :serial t
                :components ((:file "tests"))))
  :perform (test-op (o c) (uiop:symbol-call :lispfs-test '#:run)))