;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; lisp-backend.lisp --- /lisp: a live view of the running image
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; Read-only synthetic files reflecting the running Lisp, plus one writable
;;; "eval" file: write a form to it, read it back to get the result.  A
;;; filesystem REPL.

(in-package #:lispfs)

(defclass lisp-backend ()
  ((eval-result :initform "" :accessor eval-result)))

(defun room-string ()
  #+sbcl (format nil "Dynamic space usage: ~:D bytes~%Bytes consed:        ~:D~%"
                 (sb-kernel:dynamic-usage) (sb-ext:get-bytes-consed))
  #-sbcl (format nil "(room not available on this implementation)~%"))

(defun implementation-string ()
  (format nil "~A ~A~%~A / ~A~%"
          (lisp-implementation-type) (lisp-implementation-version)
          (machine-type) (software-type)))

(defun package-info-string (name)
  (let ((pkg (find-package (string-upcase name))))
    (when pkg
      (let ((present 0) (external 0))
        (do-symbols (s pkg) (declare (ignore s)) (incf present))
        (do-external-symbols (s pkg) (declare (ignore s)) (incf external))
        (format nil "name:      ~A~%nicknames: ~{~A~^ ~}~%symbols:   ~D~%external:  ~D~%"
                (package-name pkg) (package-nicknames pkg) present external)))))

(defmethod probe ((b lisp-backend) components)
  (cond
    ((null components)
     (values :dir '("features" "room" "implementation" "packages" "eval")))
    ((equal components '("features"))
     (values :file (lines->octets (sort (mapcar #'princ-to-string *features*)
                                         #'string<))))
    ((equal components '("room"))
     (values :file (string->octets (room-string))))
    ((equal components '("implementation"))
     (values :file (string->octets (implementation-string))))
    ((equal components '("eval"))
     (values :file (string->octets (eval-result b))))
    ((equal components '("packages"))
     (values :dir (sort (mapcar (lambda (p) (string-downcase (package-name p)))
                                (list-all-packages))
                        #'string<)))
    ((and (= (length components) 2) (string= (first components) "packages"))
     (let ((info (package-info-string (second components))))
       (if info (values :file (string->octets info)) :enoent)))
    (t :enoent)))

(defmethod vfs-write ((b lisp-backend) components octets offset)
  (declare (ignore offset))
  (if (equal components '("eval"))
      (progn
        (setf (eval-result b)
              (handler-case
                  (let ((form (read-from-string (octets->string octets))))
                    (format nil "~{~S~%~}" (multiple-value-list (eval form))))
                (error (e) (format nil "ERROR: ~A~%" e))))
        (length octets))
      :erofs))

;; Allow truncating eval (shells often O_TRUNC the file before writing).
(defmethod vfs-truncate ((b lisp-backend) components size)
  (declare (ignore size))
  (if (equal components '("eval")) 0 :erofs))