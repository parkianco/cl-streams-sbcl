;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: Apache-2.0

;;;; package.lisp
;;;; cl-streams-sbcl package definition

(defpackage #:cl-streams-sbcl
  (:use #:cl)
  (:nicknames #:streams-sbcl)
  (:export
   #:with-streams-sbcl-timing
   #:streams-sbcl-batch-process
   #:streams-sbcl-health-check;; Input streams
   #:make-in-memory-input-stream
   #:with-input-from-sequence
   ;; Output streams
   #:make-in-memory-output-stream
   #:get-output-stream-sequence
   #:with-output-to-sequence
   ;; Flexi streams
   #:make-flexi-stream
   #:flexi-stream
   #:flexi-stream-external-format
   ;; Stream types
   #:in-memory-input-stream
   #:in-memory-output-stream))
