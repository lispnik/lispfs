;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; mem.lisp --- A complete read/write in-memory filesystem (ramfs)
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; Backed by a tree of nodes in a hash-table.  Implements the full mutating
;;; protocol, so the mount is a genuine filesystem: create/write/read/mkdir/
;;; rename/rm all work.  Guarded by a lock (FUSE may call concurrently).

(in-package #:lispfs)

(defstruct (mnode (:constructor make-mnode (kind)))
  kind                                   ; :dir or :file
  (children (make-hash-table :test 'equal))   ; dir: name -> mnode
  ;; File bytes live in a SIMPLE (unsigned-byte 8) capacity buffer (so the FUSE
  ;; layer can take a direct pointer and bulk-memcpy).  DATA may be larger than
  ;; the logical SIZE -- it grows by doubling, giving amortized O(1) append
  ;; instead of recopying the whole file on every write chunk.
  (data (make-array 0 :element-type '(unsigned-byte 8)))
  (size 0))

(defclass mem-backend ()
  ((root :initform (make-mnode :dir) :reader mem-root)
   (lock :initform (make-lock-portable) :reader mem-lock)))

(defun make-lock-portable ()
  #+sbcl (sb-thread:make-mutex :name "lispfs-mem")
  #-sbcl nil)

(defmacro with-mem-lock ((backend) &body body)
  #+sbcl `(sb-thread:with-mutex ((mem-lock ,backend)) ,@body)
  #-sbcl `(progn ,backend ,@body))

(defun walk (root components)
  "Return the node at COMPONENTS under ROOT, or NIL."
  (let ((node root))
    (dolist (c components node)
      (unless (and node (eq (mnode-kind node) :dir))
        (return-from walk nil))
      (setf node (gethash c (mnode-children node))))))

(defun walk-parent (root components)
  "Return (values parent-node last-name) for COMPONENTS, or NIL if no parent
directory exists.  COMPONENTS must be non-empty."
  (when components
    (let ((parent (walk root (butlast components))))
      (when (and parent (eq (mnode-kind parent) :dir))
        (values parent (car (last components)))))))

(defmethod probe ((b mem-backend) components)
  (with-mem-lock (b)
    (let ((node (walk (mem-root b) components)))
      (cond ((null node) :enoent)
            ((eq (mnode-kind node) :dir)
             (let (names)
               (maphash (lambda (k v) (declare (ignore v)) (push k names))
                        (mnode-children node))
               (values :dir (sort names #'string<))))
            (t (values :file (mnode-data node) (mnode-size node)))))))

(defmethod vfs-mkdir ((b mem-backend) components)
  (with-mem-lock (b)
    (multiple-value-bind (parent name) (walk-parent (mem-root b) components)
      (cond ((null parent) :enoent)
            ((gethash name (mnode-children parent)) :eexist)
            (t (setf (gethash name (mnode-children parent)) (make-mnode :dir)) 0)))))

(defmethod vfs-create ((b mem-backend) components)
  (with-mem-lock (b)
    (multiple-value-bind (parent name) (walk-parent (mem-root b) components)
      (cond ((null parent) :enoent)
            ((gethash name (mnode-children parent)) :eexist)
            (t (setf (gethash name (mnode-children parent)) (make-mnode :file)) 0)))))

(defmethod vfs-write ((b mem-backend) components octets offset)
  (with-mem-lock (b)
    (let ((node (walk (mem-root b) components)))
      (cond ((null node) :enoent)
            ((eq (mnode-kind node) :dir) :eisdir)
            (t (let* ((cur (mnode-size node))
                      (end (+ offset (length octets))))
                 ;; ensure capacity (double on growth -> amortized O(1) append)
                 (when (> end (length (mnode-data node)))
                   (let ((new (make-array (max end (* 2 (length (mnode-data node))) 64)
                                          :element-type '(unsigned-byte 8))))
                     (replace new (mnode-data node) :end2 cur)
                     (setf (mnode-data node) new)))
                 (let ((data (mnode-data node)))
                   (when (> offset cur)            ; zero a gap past old end
                     (fill data 0 :start cur :end offset))
                   (replace data octets :start1 offset))
                 (setf (mnode-size node) (max cur end))
                 (length octets)))))))

(defmethod vfs-truncate ((b mem-backend) components size)
  (with-mem-lock (b)
    (let ((node (walk (mem-root b) components)))
      (cond ((null node) :enoent)
            ((eq (mnode-kind node) :dir) :eisdir)
            (t (let ((cur (mnode-size node)))
                 (cond ((= size cur))
                       ((< size cur) (setf (mnode-size node) size)) ; shrink: keep cap
                       (t ;; grow: ensure capacity, zero the new region
                        (when (> size (length (mnode-data node)))
                          (let ((new (make-array size :element-type '(unsigned-byte 8))))
                            (replace new (mnode-data node) :end2 cur)
                            (setf (mnode-data node) new)))
                        (fill (mnode-data node) 0 :start cur :end size)
                        (setf (mnode-size node) size))))
               0)))))

(defmethod vfs-unlink ((b mem-backend) components)
  (with-mem-lock (b)
    (multiple-value-bind (parent name) (walk-parent (mem-root b) components)
      (let ((node (and parent (gethash name (mnode-children parent)))))
        (cond ((null node) :enoent)
              ((eq (mnode-kind node) :dir) :eisdir)
              (t (remhash name (mnode-children parent)) 0))))))

(defmethod vfs-rmdir ((b mem-backend) components)
  (with-mem-lock (b)
    (multiple-value-bind (parent name) (walk-parent (mem-root b) components)
      (let ((node (and parent (gethash name (mnode-children parent)))))
        (cond ((null node) :enoent)
              ((not (eq (mnode-kind node) :dir)) :enotdir)
              ((plusp (hash-table-count (mnode-children node))) :enotempty)
              (t (remhash name (mnode-children parent)) 0))))))

(defmethod vfs-rename ((b mem-backend) from to)
  (with-mem-lock (b)
    (let ((node (walk (mem-root b) from)))
      (if (null node)
          :enoent
          (multiple-value-bind (fp fn) (walk-parent (mem-root b) from)
            (multiple-value-bind (tp tn) (walk-parent (mem-root b) to)
              (cond ((or (null fp) (null tp)) :enoent)
                    (t (setf (gethash tn (mnode-children tp)) node)
                       (remhash fn (mnode-children fp))
                       0))))))))