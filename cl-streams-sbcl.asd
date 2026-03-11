;;;; cl-streams-sbcl.asd
;;;; Flexible binary/character streams with ZERO external dependencies

(asdf:defsystem #:cl-streams-sbcl
  :description "Flexible binary/character streams for SBCL"
  :author "Parkian Company LLC"
  :license "BSD-3-Clause"
  :version "1.0.0"
  :serial t
  :components ((:file "package")
               (:module "src"
                :components ((:file "streams")))))
