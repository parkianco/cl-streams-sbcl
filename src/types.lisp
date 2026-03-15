;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package #:cl-streams-sbcl)

;;; Core types for cl-streams-sbcl
(deftype cl-streams-sbcl-id () '(unsigned-byte 64))
(deftype cl-streams-sbcl-status () '(member :ready :active :error :shutdown))
