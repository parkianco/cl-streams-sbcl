;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; src/streams.lisp
;;;; Flexible binary/character streams for SBCL

(in-package #:cl-streams-sbcl)

;;; In-memory input stream

(defclass in-memory-input-stream (sb-gray:fundamental-binary-input-stream)
  ((data :initarg :data :accessor stream-data)
   (position :initform 0 :accessor stream-position))
  (:documentation "A binary input stream reading from a byte sequence."))

(defmethod sb-gray:stream-read-byte ((stream in-memory-input-stream))
  (with-slots (data position) stream
    (if (< position (length data))
        (prog1 (aref data position)
          (incf position))
        :eof)))

;; Note: sequence reading is handled by the default implementation
;; which uses stream-read-byte repeatedly. For better performance,
;; users can call read-sequence directly on the data slot.

(defmethod sb-gray:stream-listen ((stream in-memory-input-stream))
  (with-slots (data position) stream
    (< position (length data))))

(defmethod stream-element-type ((stream in-memory-input-stream))
  '(unsigned-byte 8))

(defun make-in-memory-input-stream (sequence)
  "Create an input stream reading from SEQUENCE (a byte vector or list)."
  (let ((data (etypecase sequence
                ((vector (unsigned-byte 8)) sequence)
                (vector (coerce sequence '(vector (unsigned-byte 8))))
                (list (coerce sequence '(vector (unsigned-byte 8)))))))
    (make-instance 'in-memory-input-stream :data data)))

(defmacro with-input-from-sequence ((var sequence) &body body)
  "Execute BODY with VAR bound to an input stream reading from SEQUENCE."
  `(let ((,var (make-in-memory-input-stream ,sequence)))
     ,@body))

;;; In-memory output stream

(defclass in-memory-output-stream (sb-gray:fundamental-binary-output-stream)
  ((data :initform (make-array 256 :element-type '(unsigned-byte 8)
                                   :adjustable t :fill-pointer 0)
         :accessor stream-data))
  (:documentation "A binary output stream accumulating to a byte vector."))

(defmethod sb-gray:stream-write-byte ((stream in-memory-output-stream) byte)
  (vector-push-extend byte (stream-data stream))
  byte)

;; Note: sequence writing is handled by the default implementation
;; which uses stream-write-byte repeatedly.

(defmethod stream-element-type ((stream in-memory-output-stream))
  '(unsigned-byte 8))

(defun make-in-memory-output-stream ()
  "Create an output stream that accumulates bytes."
  (make-instance 'in-memory-output-stream))

(defun get-output-stream-sequence (stream)
  "Return the accumulated bytes from an in-memory-output-stream."
  (copy-seq (stream-data stream)))

(defmacro with-output-to-sequence ((var) &body body)
  "Execute BODY with VAR bound to an output stream, return accumulated bytes."
  (let ((stream-var (gensym "STREAM")))
    `(let* ((,stream-var (make-in-memory-output-stream))
            (,var ,stream-var))
       ,@body
       (get-output-stream-sequence ,stream-var))))

;;; Flexi stream (character/binary with encoding)

(defclass flexi-stream (sb-gray:fundamental-character-input-stream
                        sb-gray:fundamental-character-output-stream)
  ((underlying :initarg :stream :accessor flexi-stream-underlying)
   (external-format :initarg :external-format :accessor flexi-stream-external-format
                    :initform :utf-8)
   (read-buffer :initform nil :accessor flexi-stream-read-buffer)
   (read-pos :initform 0 :accessor flexi-stream-read-pos))
  (:documentation "A stream wrapper with configurable character encoding."))

(defun make-flexi-stream (stream &key (external-format :utf-8))
  "Wrap STREAM with encoding support. EXTERNAL-FORMAT is :UTF-8, :ASCII, or :LATIN-1."
  (make-instance 'flexi-stream
                 :stream stream
                 :external-format external-format))

(defmethod sb-gray:stream-read-char ((stream flexi-stream))
  (let* ((underlying (flexi-stream-underlying stream))
         (format (flexi-stream-external-format stream)))
    (case format
      (:ascii
       (let ((byte (read-byte underlying nil :eof)))
         (if (eq byte :eof) :eof (code-char byte))))
      (:latin-1
       (let ((byte (read-byte underlying nil :eof)))
         (if (eq byte :eof) :eof (code-char byte))))
      (:utf-8
       (let ((b1 (read-byte underlying nil :eof)))
         (cond ((eq b1 :eof) :eof)
               ((< b1 #x80) (code-char b1))
               ((< b1 #xc0) (code-char #xFFFD))  ; Invalid
               ((< b1 #xe0)
                (let ((b2 (read-byte underlying nil 0)))
                  (code-char (logior (ash (logand b1 #x1f) 6)
                                     (logand b2 #x3f)))))
               ((< b1 #xf0)
                (let ((b2 (read-byte underlying nil 0))
                      (b3 (read-byte underlying nil 0)))
                  (code-char (logior (ash (logand b1 #x0f) 12)
                                     (ash (logand b2 #x3f) 6)
                                     (logand b3 #x3f)))))
               (t
                (let ((b2 (read-byte underlying nil 0))
                      (b3 (read-byte underlying nil 0))
                      (b4 (read-byte underlying nil 0)))
                  (code-char (logior (ash (logand b1 #x07) 18)
                                     (ash (logand b2 #x3f) 12)
                                     (ash (logand b3 #x3f) 6)
                                     (logand b4 #x3f)))))))))))

(defmethod sb-gray:stream-write-char ((stream flexi-stream) char)
  (let* ((underlying (flexi-stream-underlying stream))
         (format (flexi-stream-external-format stream))
         (code (char-code char)))
    (case format
      ((:ascii :latin-1)
       (write-byte (logand code #xff) underlying))
      (:utf-8
       (cond ((< code #x80)
              (write-byte code underlying))
             ((< code #x800)
              (write-byte (logior #xc0 (ash code -6)) underlying)
              (write-byte (logior #x80 (logand code #x3f)) underlying))
             ((< code #x10000)
              (write-byte (logior #xe0 (ash code -12)) underlying)
              (write-byte (logior #x80 (logand (ash code -6) #x3f)) underlying)
              (write-byte (logior #x80 (logand code #x3f)) underlying))
             (t
              (write-byte (logior #xf0 (ash code -18)) underlying)
              (write-byte (logior #x80 (logand (ash code -12) #x3f)) underlying)
              (write-byte (logior #x80 (logand (ash code -6) #x3f)) underlying)
              (write-byte (logior #x80 (logand code #x3f)) underlying)))))
    char))

(defmethod sb-gray:stream-line-column ((stream flexi-stream))
  nil)

(defmethod close ((stream flexi-stream) &key abort)
  (close (flexi-stream-underlying stream) :abort abort))
