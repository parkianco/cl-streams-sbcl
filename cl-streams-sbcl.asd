;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; cl-streams-sbcl.asd
;;;; Flexible binary/character streams with ZERO external dependencies

(asdf:defsystem #:cl-streams-sbcl
  :description "Flexible binary/character streams for SBCL"
  :author "Park Ian Co"
  :license "Apache-2.0"
  :version "0.1.0"
  :serial t
  :components ((:file "package")
               (:module "src"
                :components ((:file "package")
                             (:file "conditions" :depends-on ("package"))
                             (:file "types" :depends-on ("package"))
                             (:file "cl-streams-sbcl" :depends-on ("package" "conditions" "types")))))))

(asdf:defsystem #:cl-streams-sbcl/test
  :description "Tests for cl-streams-sbcl"
  :depends-on (#:cl-streams-sbcl)
  :serial t
  :components ((:module "test"
                :components ((:file "test-streams-sbcl"))))
  :perform (asdf:test-op (o c)
             (let ((result (uiop:symbol-call :cl-streams-sbcl.test :run-tests)))
               (unless result
                 (error "Tests failed")))))
