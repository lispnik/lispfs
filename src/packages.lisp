;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; packages.lisp --- Package for the lispfs core
;;;
;;; See COPYRIGHT (MIT).

(defpackage #:lispfs
  (:use #:cl)
  (:export
   ;; protocol
   #:probe #:vfs-write #:vfs-create #:vfs-mkdir #:vfs-unlink #:vfs-rmdir
   #:vfs-truncate #:vfs-rename
   ;; helpers
   #:split-path #:string->octets #:octets->string
   ;; backends + assembly
   #:router #:mem-backend #:lisp-backend #:compute-backend
   #:make-default-root))