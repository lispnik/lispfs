;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; package.lisp --- Package for the FUSE binding (and the grovel file)
;;;
;;; See COPYRIGHT (MIT).

(defpackage #:lispfs.fuse
  (:use #:cl)
  (:export #:mount #:*root*))