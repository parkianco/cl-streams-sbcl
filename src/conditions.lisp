;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-streams-sbcl)

(define-condition cl-streams-sbcl-error (error)
  ((message :initarg :message :reader cl-streams-sbcl-error-message))
  (:report (lambda (condition stream)
             (format stream "cl-streams-sbcl error: ~A" (cl-streams-sbcl-error-message condition)))))
