;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; fuse.lisp --- Fill struct fuse_operations with Lisp closures and mount
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; Each FUSE operation is a libffi closure (cffi-callback-closures:
;;; make-foreign-callback) that translates the C call to/from the lispfs VFS
;;; protocol.  fuse_main_real then runs the loop; in single-threaded mode the
;;; callbacks run on the thread that called MOUNT, so they execute on a real
;;; Lisp thread.

(in-package #:lispfs.fuse)

(cffi:define-foreign-library libfuse
  (:darwin (:or "libfuse.2.dylib" "/usr/local/lib/libfuse.2.dylib" "libfuse.dylib"))
  (:unix  (:or "libfuse.so.2" "libfuse.so"))
  (t (:default "libfuse")))
(cffi:use-foreign-library libfuse)

;; fuse_main is a macro for fuse_main_real(argc, argv, op, sizeof(*op), priv).
(cffi:defcfun ("fuse_main_real" %fuse-main-real) :int
  (argc :int) (argv :pointer) (op :pointer)
  (op-size :unsigned-long) (private :pointer))

(defvar *root* nil "The lispfs router this mount serves.")
(defvar *callbacks* nil "Live op callbacks, kept reachable while mounted.")

(defun errno-of (keyword)
  "Map a VFS error keyword to a negative errno."
  (- (ecase keyword
       (:enoent +enoent+) (:erofs +erofs+) (:eexist +eexist+)
       (:enotempty +enotempty+) (:eisdir +eisdir+) (:enotdir +enotdir+)
       (:eacces +eacces+))))

(defun ret (result)
  "A mutator returned 0 or an error keyword; turn it into a FUSE status."
  (if (integerp result) result (errno-of result)))

(defun zero-foreign (ptr nbytes)
  (dotimes (i nbytes) (setf (cffi:mem-aref ptr :uint8 i) 0)))

(defun %memcpy (dest src n)
  (cffi:foreign-funcall "memcpy" :pointer dest :pointer src size-t n :pointer))

(defun copy-out (data buf start count)
  "Bulk-copy COUNT bytes of simple octet-vector DATA (from START) into BUF."
  (when (plusp count)
    (cffi:with-pointer-to-vector-data (src data)
      (%memcpy buf (cffi:inc-pointer src start) count))))

(defun copy-in (buf count)
  "Bulk-copy COUNT bytes from foreign BUF into a fresh simple octet vector."
  (let ((v (make-array count :element-type '(unsigned-byte 8))))
    (when (plusp count)
      (cffi:with-pointer-to-vector-data (dst v)
        (%memcpy dst buf count)))
    v))

(defmacro defop (name (&rest lambda-list) arg-types &body body)
  "Define a constructor (MAKE-NAME) returning a foreign callback for an op.
Wraps the body so a Lisp error returns -EIO rather than crashing the mount."
  `(defun ,(intern (format nil "MAKE-~A" name)) ()
     (cffi-callback-closures:make-foreign-callback
      (lambda ,lambda-list
        (handler-case (locally ,@body)
          (error (e)
            (format *error-output* "~&lispfs ~(~A~) error: ~A~%" ',name e)
            (- +eio+))))
      :int ',arg-types)))

(defop getattr (path stbuf) (:string :pointer)
  (multiple-value-bind (kind val size) (lispfs:probe *root* (lispfs:split-path path))
    (if (eq kind :enoent)
        (- +enoent+)
        (progn
          (zero-foreign stbuf (cffi:foreign-type-size '(:struct stat)))
          (macrolet ((set% (slot v) `(setf (cffi:foreign-slot-value
                                            stbuf '(:struct stat) ',slot) ,v)))
            ;; own the files so the mounting user can write them
            (set% uid (cffi:foreign-funcall "getuid" :uint32))
            (set% gid (cffi:foreign-funcall "getgid" :uint32))
            (ecase kind
              (:dir  (set% mode (logior +s-ifdir+ #o755)) (set% nlink 2) (set% size 0))
              (:file (set% mode (logior +s-ifreg+ #o644)) (set% nlink 1)
                     (set% size (or size (length val))))))
          0))))

(defop readdir (path buf filler offset fi)
    (:string :pointer :pointer off-t :pointer)
  (declare (ignore offset fi))
  (multiple-value-bind (kind names) (lispfs:probe *root* (lispfs:split-path path))
    (if (eq kind :dir)
        (flet ((emit (name)
                 (cffi:foreign-funcall-pointer
                  filler () :pointer buf :string name
                  :pointer (cffi:null-pointer) :int64 0 :int)))
          (emit ".") (emit "..")
          (dolist (n names) (emit n))
          0)
        (- +enoent+))))

(defop open (path fi) (:string :pointer)
  (declare (ignore fi))
  (if (eq (lispfs:probe *root* (lispfs:split-path path)) :enoent) (- +enoent+) 0))

(defop read (path buf size offset fi)
    (:string :pointer size-t off-t :pointer)
  (declare (ignore fi))
  (multiple-value-bind (kind data fsize) (lispfs:probe *root* (lispfs:split-path path))
    (if (not (eq kind :file))
        (- +enoent+)
        (let* ((len (or fsize (length data)))
               (start (min offset len))
               (count (max 0 (min size (- len start)))))
          (copy-out data buf start count)
          count))))

(defop write (path buf size offset fi)
    (:string :pointer size-t off-t :pointer)
  (declare (ignore fi))
  (ret (lispfs:vfs-write *root* (lispfs:split-path path) (copy-in buf size) offset)))

(defop create (path mode fi) (:string mode-t :pointer)
  (declare (ignore mode fi))
  (ret (lispfs:vfs-create *root* (lispfs:split-path path))))

(defop mkdir (path mode) (:string mode-t)
  (declare (ignore mode))
  (ret (lispfs:vfs-mkdir *root* (lispfs:split-path path))))

(defop unlink (path) (:string)
  (ret (lispfs:vfs-unlink *root* (lispfs:split-path path))))

(defop rmdir (path) (:string)
  (ret (lispfs:vfs-rmdir *root* (lispfs:split-path path))))

(defop rename (from to) (:string :string)
  (ret (lispfs:vfs-rename *root* (lispfs:split-path from) (lispfs:split-path to))))

(defop truncate (path size) (:string off-t)
  (ret (lispfs:vfs-truncate *root* (lispfs:split-path path) size)))

(defop utimens (path tv) (:string :pointer)
  (declare (ignore tv))
  0)                                    ; accept touch, ignore times

(defmacro with-foreign-argv ((argv argc args) &body body)
  `(let* ((arglist ,args) (,argc (length arglist))
          (strs (mapcar #'cffi:foreign-string-alloc arglist)))
     (cffi:with-foreign-object (,argv :pointer ,argc)
       (unwind-protect
            (progn
              (loop for i from 0 for s in strs
                    do (setf (cffi:mem-aref ,argv :pointer i) s))
              ,@body)
         (mapc #'cffi:foreign-string-free strs)))))

(defun mount (mountpoint &key (root (lispfs:make-default-root)) (debug nil))
  "Mount the lispfs filesystem at MOUNTPOINT.  Blocks running the FUSE loop
until the filesystem is unmounted (umount MOUNTPOINT).  Single-threaded, so the
op closures run on this thread."
  (setf *root* root *callbacks* '())
  (ensure-directories-exist (uiop:ensure-directory-pathname mountpoint))
  (let ((ops (cffi:foreign-alloc '(:struct fuse-operations))))
    (zero-foreign ops (cffi:foreign-type-size '(:struct fuse-operations)))
    (flet ((slot (name cb)
             (setf (cffi:foreign-slot-value ops '(:struct fuse-operations) name) cb)
             (push cb *callbacks*)))
      (slot 'getattr (make-getattr))   (slot 'readdir (make-readdir))
      (slot 'open    (make-open))      (slot 'read    (make-read))
      (slot 'write   (make-write))     (slot 'create  (make-create))
      (slot 'mkdir   (make-mkdir))     (slot 'unlink  (make-unlink))
      (slot 'rmdir   (make-rmdir))     (slot 'rename  (make-rename))
      (slot 'truncate (make-truncate)) (slot 'utimens (make-utimens)))
    (with-foreign-argv (argv argc (append (list "lispfs" mountpoint "-s" "-f")
                                          (when debug '("-d"))))
      (%fuse-main-real argc argv ops
                       (cffi:foreign-type-size '(:struct fuse-operations))
                       (cffi:null-pointer)))))