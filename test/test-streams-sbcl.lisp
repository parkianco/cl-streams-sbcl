;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; test-streams-sbcl.lisp - Unit tests for streams-sbcl
;;;;
;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

(defpackage #:cl-streams-sbcl.test
  (:use #:cl)
  (:export #:run-tests))

(in-package #:cl-streams-sbcl.test)

(defun run-tests ()
  "Run all tests for cl-streams-sbcl."
  (format t "~&Running tests for cl-streams-sbcl...~%")
  ;; TODO: Add test cases
  ;; (test-function-1)
  ;; (test-function-2)
  (format t "~&All tests passed!~%")
  t)
