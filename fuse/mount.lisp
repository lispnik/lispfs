;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; mount.lisp --- Convenience launcher: load the system and mount.
;;;
;;; Run from this project directory:
;;;
;;;   sbcl --load fuse/mount.lisp --eval '(lispfs.fuse:mount "/tmp/lispfs")'
;;;
;;; or with a mountpoint argument:
;;;
;;;   sbcl --load fuse/mount.lisp /tmp/lispfs
;;;
;;; The mount blocks (single-threaded, foreground) until you unmount it from
;;; another shell:  umount /tmp/lispfs

(require :asdf)

;; Find lispfs (this dir) plus cffi-callback-closures and its deps.  Adjust the
;; tree root if your checkout lives elsewhere.
(asdf:initialize-source-registry
 (list :source-registry
       (list :tree (or (uiop:getenvp "LISPFS_REGISTRY")
                       #p"/Users/mkennedy/Projects/common-lisp/"))
       :inherit-configuration))

(asdf:load-system :lispfs-fuse)

;; If a mountpoint was passed on the command line, mount it now.
(let ((mp (first (uiop:command-line-arguments))))
  (when mp
    (format t "~&Mounting lispfs at ~A  (unmount with: umount ~A)~%" mp mp)
    (finish-output)
    (funcall (read-from-string "lispfs.fuse:mount") mp)))