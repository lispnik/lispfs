;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; tests.lisp --- In-process VFS tests (no mount required)
;;;
;;; See COPYRIGHT (MIT).

(defpackage #:lispfs-test
  (:use #:cl #:lispfs)
  (:export #:run))

(in-package #:lispfs-test)

(defmacro check (form)
  `(progn (assert ,form () "check failed: ~S" ',form)
          (format t "~&  ok: ~S~%" ',form)))

(defun p (root path)
  "Probe and normalize: returns (:dir names) | (:file string) | :enoent."
  (multiple-value-bind (kind val sz) (probe root (split-path path))
    (case kind
      (:dir (list :dir (sort (copy-list val) #'string<)))
      (:file (list :file (octets->string (subseq val 0 (or sz (length val))))))
      (t kind))))

(defun run ()
  (let ((root (make-default-root)))
    (format t "~&lispfs core tests~%=================~%")

    ;; router
    (check (equal (p root "/") '(:dir ("compute" "lisp" "mem"))))

    ;; compute backend (pure functions of the path)
    (check (equal (p root "/compute/fib/10")    '(:file "55
")))
    (check (equal (p root "/compute/reverse/hello") '(:file "olleh
")))
    (check (equal (p root "/compute/primes/20") '(:file "2 3 5 7 11 13 17 19
")))
    (check (eq (p root "/compute/fib/banana") :enoent))

    ;; lisp backend (live image)
    (check (eq (first (multiple-value-list (probe root (split-path "/lisp/room")))) :file))
    (check (search "Common Lisp" (concatenate 'string "Common Lisp"))) ; sanity
    (check (member "common-lisp" (second (p root "/lisp/packages")) :test #'string=))

    ;; lisp eval: write a form, read the result
    (check (= 7 (vfs-write root (split-path "/lisp/eval")
                           (string->octets "(+ 3 4)") 0)))   ; 7 bytes written
    (check (equal (p root "/lisp/eval") '(:file "7
")))

    ;; mem backend: the full read/write lifecycle
    (check (equal (p root "/mem") '(:dir ())))
    (check (= 0 (vfs-create root (split-path "/mem/note.txt"))))
    (check (= 5 (vfs-write root (split-path "/mem/note.txt")
                           (string->octets "hello") 0)))
    (check (equal (p root "/mem/note.txt") '(:file "hello")))
    (check (= 6 (vfs-write root (split-path "/mem/note.txt")
                           (string->octets " world") 5)))     ; append at offset
    (check (equal (p root "/mem/note.txt") '(:file "hello world")))
    (check (= 0 (vfs-mkdir root (split-path "/mem/sub"))))
    (check (= 0 (vfs-rename root (split-path "/mem/note.txt")
                            (split-path "/mem/sub/note.txt"))))
    (check (equal (p root "/mem") '(:dir ("sub"))))
    (check (equal (p root "/mem/sub") '(:dir ("note.txt"))))
    (check (equal (p root "/mem/sub/note.txt") '(:file "hello world")))
    (check (= 0 (vfs-truncate root (split-path "/mem/sub/note.txt") 5)))
    (check (equal (p root "/mem/sub/note.txt") '(:file "hello")))
    (check (= 0 (vfs-unlink root (split-path "/mem/sub/note.txt"))))
    (check (eq (p root "/mem/sub/note.txt") :enoent))
    (check (= 0 (vfs-rmdir root (split-path "/mem/sub"))))
    (check (equal (p root "/mem") '(:dir ())))

    ;; errors
    (check (eq (vfs-mkdir root (split-path "/compute/x")) :erofs))
    (check (eq (p root "/nope") :enoent))

    (format t "~&All lispfs core tests passed.~%")
    t))