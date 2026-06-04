;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; compute.lisp --- /compute: files are pure functions of their path
;;;
;;; See COPYRIGHT (MIT).
;;;
;;; /compute/fib/30, /compute/primes/40, /compute/reverse/hello, etc.  The path
;;; is the program; reading it runs the computation.  /compute/random yields
;;; fresh bytes on every read.

(in-package #:lispfs)

(defclass compute-backend () ())

(defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(defun primes-upto (n)
  (let ((sieve (make-array (1+ (max n 1)) :initial-element t)))
    (loop for i from 2 to n
          when (aref sieve i)
            collect i
            and do (loop for j from (* i i) to n by i do (setf (aref sieve j) nil)))))

(defun parse-nat (s)
  (let ((n (ignore-errors (parse-integer s))))
    (and n (>= n 0) n)))

(defparameter *functions* '("fib" "primes" "reverse" "upcase" "random"))

(defmethod probe ((b compute-backend) components)
  (cond
    ((null components) (values :dir *functions*))
    ;; the function names are directories (their argument is the next path
    ;; component); listing them yields nothing.
    ((and (= (length components) 1) (string= (first components) "random"))
     (values :file (string->octets
                    (format nil "~{~2,'0X~}~%"
                            (loop repeat 16 collect (random 256))))))
    ((and (= (length components) 1) (member (first components) *functions*
                                            :test #'string=))
     (values :dir '()))
    ((= (length components) 2)
     (destructuring-bind (fn arg) components
       (flet ((ok (s) (values :file (string->octets s))))
         (cond
           ((string= fn "reverse") (ok (format nil "~A~%" (reverse arg))))
           ((string= fn "upcase")  (ok (format nil "~A~%" (string-upcase arg))))
           ((string= fn "fib")
            (let ((n (parse-nat arg)))
              (if (and n (<= n 90)) (ok (format nil "~D~%" (fib n))) :enoent)))
           ((string= fn "primes")
            (let ((n (parse-nat arg)))
              (if n (ok (format nil "~{~D~^ ~}~%" (primes-upto n))) :enoent)))
           (t :enoent)))))
    (t :enoent)))