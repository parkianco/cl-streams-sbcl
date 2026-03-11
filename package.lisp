;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; package.lisp
;;;; cl-streams-sbcl package definition

(defpackage #:cl-streams-sbcl
  (:use #:cl)
  (:nicknames #:streams-sbcl)
  (:export
   ;; Input streams
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
