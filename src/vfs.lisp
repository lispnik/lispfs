;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; vfs.lisp --- The virtual-filesystem protocol and the path router
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; A "backend" answers PROBE for a path (given as a list of components) and,
;;; optionally, the mutating operations.  PROBE returns one of:
;;;
;;;   (values :dir  list-of-child-name-strings)
;;;   (values :file simple-octet-vector &optional logical-size)
;;;   (values :enoent)
;;;
;;; For :file, LOGICAL-SIZE (if given) is the valid byte count, which may be
;;; smaller than (length vector) when a backend over-allocates (see mem.lisp).
;;; Callers use LOGICAL-SIZE (defaulting to the vector length) as the file size
;;; and must not read past it.
;;;
;;; Mutators return 0 on success or a keyword error (:enoent :erofs :eexist
;;; :enotempty :eisdir :enotdir).  The FUSE layer maps these to errno.

(in-package #:lispfs)

(deftype octets () '(array (unsigned-byte 8) (*)))

(defun split-path (path)
  "\"/a/b\" => (\"a\" \"b\");  \"/\" or \"\" => ()."
  (remove "" (uiop:split-string path :separator "/") :test #'string=))

(defun string->octets (string)
  (babel-or-native string))

(defun babel-or-native (string)
  #+sbcl (sb-ext:string-to-octets string :external-format :utf-8)
  #-sbcl (map '(vector (unsigned-byte 8)) #'char-code string))

(defun octets->string (octets)
  #+sbcl (sb-ext:octets-to-string (coerce octets '(vector (unsigned-byte 8)))
                                  :external-format :utf-8)
  #-sbcl (map 'string #'code-char octets))

(defun lines->octets (lines)
  "Join LINES (strings) with newlines into a trailing-newline octet vector."
  (string->octets (format nil "~{~A~%~}" lines)))

;;;; ---- protocol --------------------------------------------------------

(defgeneric probe (backend components)
  (:documentation "See file header."))

(defgeneric vfs-write (backend components octets offset)
  (:method (backend components octets offset)
    (declare (ignore backend components octets offset)) :erofs))
(defgeneric vfs-create (backend components)
  (:method (backend components) (declare (ignore backend components)) :erofs))
(defgeneric vfs-mkdir (backend components)
  (:method (backend components) (declare (ignore backend components)) :erofs))
(defgeneric vfs-unlink (backend components)
  (:method (backend components) (declare (ignore backend components)) :erofs))
(defgeneric vfs-rmdir (backend components)
  (:method (backend components) (declare (ignore backend components)) :erofs))
(defgeneric vfs-truncate (backend components size)
  (:method (backend components size) (declare (ignore backend components size)) :erofs))
(defgeneric vfs-rename (backend from to)
  (:method (backend from to) (declare (ignore backend from to)) :erofs))

;;;; ---- router ----------------------------------------------------------
;;;
;;; The root is a router: its top-level entries are named sub-backends, and it
;;; delegates each operation to the sub-backend owning the first path
;;; component.

(defclass router ()
  ((mounts :initarg :mounts :accessor mounts
           :documentation "Alist of (name-string . backend).")))

(defun route (router components)
  "Return (values backend rest) for COMPONENTS, or NIL if unrouted."
  (let ((entry (assoc (first components) (mounts router) :test #'string=)))
    (when entry (values (cdr entry) (rest components)))))

(defmethod probe ((r router) components)
  (if (null components)
      (values :dir (mapcar #'car (mounts r)))
      (multiple-value-bind (backend rest) (route r components)
        (if backend (probe backend rest) :enoent))))

(macrolet ((delegate (gf (&rest extra))
             `(defmethod ,gf ((r router) components ,@extra)
                (multiple-value-bind (backend rest) (route r components)
                  (if backend (,gf backend rest ,@extra) :enoent)))))
  (delegate vfs-write (octets offset))
  (delegate vfs-create ())
  (delegate vfs-mkdir ())
  (delegate vfs-unlink ())
  (delegate vfs-rmdir ())
  (delegate vfs-truncate (size)))

(defmethod vfs-rename ((r router) from to)
  ;; Only support rename within a single sub-backend.
  (multiple-value-bind (bf rf) (route r from)
    (multiple-value-bind (bt rt) (route r to)
      (if (and bf (eq bf bt)) (vfs-rename bf rf rt) :erofs))))

(defun make-default-root ()
  "Assemble the hybrid filesystem: a writable scratch area, a live-image view,
and a computed-file area."
  (make-instance 'router
                 :mounts (list (cons "mem"     (make-instance 'mem-backend))
                               (cons "lisp"    (make-instance 'lisp-backend))
                               (cons "compute" (make-instance 'compute-backend)))))