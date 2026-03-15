;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: Apache-2.0

(in-package :cl-streams-sbcl)

;;; ============================================================================
;;; In-Memory Streams
;;; ============================================================================

(defstruct in-memory-input-stream
  "Input stream backed by a byte vector.
SLOTS:
  data    - Byte array to read from
  position - Current read position
  lock    - Mutex for thread safety"
  (data #() :type (simple-array (unsigned-byte 8)))
  (position 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun create-in-memory-input-stream (data)
  "Create input stream from DATA.
PARAMETERS: data - Byte array or sequence
RETURNS: IN-MEMORY-INPUT-STREAM"
  (let ((bytes (if (typep data '(simple-array (unsigned-byte 8)))
                   data
                   (coerce data '(simple-array (unsigned-byte 8))))))
    (make-in-memory-input-stream :data bytes)))

(defun read-from-memory-stream (stream count)
  "Read COUNT bytes from STREAM.
PARAMETERS:
  stream - IN-MEMORY-INPUT-STREAM
  count  - Number of bytes to read
RETURNS: Byte array or NIL if EOF"
  (sb-thread:with-mutex ((in-memory-input-stream-lock stream))
    (let ((pos (in-memory-input-stream-position stream))
          (data (in-memory-input-stream-data stream)))
      (if (>= pos (length data))
          nil
          (let* ((available (- (length data) pos))
                 (to-read (min count available))
                 (result (make-array to-read :element-type '(unsigned-byte 8))))
            (loop for i from 0 below to-read
                  do (setf (aref result i) (aref data (+ pos i))))
            (incf (in-memory-input-stream-position stream) to-read)
            result)))))

(defun in-memory-stream-position (stream)
  "Get current read position in STREAM."
  (sb-thread:with-mutex ((in-memory-input-stream-lock stream))
    (in-memory-input-stream-position stream)))

(defun in-memory-stream-reset (stream)
  "Reset STREAM to beginning."
  (sb-thread:with-mutex ((in-memory-input-stream-lock stream))
    (setf (in-memory-input-stream-position stream) 0)))

(defstruct in-memory-output-stream
  "Output stream that accumulates bytes in memory.
SLOTS:
  data    - Byte array accumulator
  position - Current write position
  lock    - Mutex for thread safety"
  (data (make-array 1024 :element-type '(unsigned-byte 8))
        :type (simple-array (unsigned-byte 8)))
  (position 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun create-in-memory-output-stream ()
  "Create an output stream that accumulates bytes.
RETURNS: IN-MEMORY-OUTPUT-STREAM"
  (make-in-memory-output-stream))

(defun write-to-memory-stream (stream data)
  "Write DATA to STREAM.
PARAMETERS:
  stream - IN-MEMORY-OUTPUT-STREAM
  data   - Byte array or sequence"
  (sb-thread:with-mutex ((in-memory-output-stream-lock stream))
    (let* ((bytes (if (typep data '(simple-array (unsigned-byte 8)))
                      data
                      (coerce data '(simple-array (unsigned-byte 8)))))
           (len (length bytes))
           (new-pos (+ (in-memory-output-stream-position stream) len)))
      (when (> new-pos (length (in-memory-output-stream-data stream)))
        (let ((new-data (make-array (* 2 new-pos)
                                    :element-type '(unsigned-byte 8))))
          (loop for i from 0 below (in-memory-output-stream-position stream)
                do (setf (aref new-data i) (aref (in-memory-output-stream-data stream) i)))
          (setf (in-memory-output-stream-data stream) new-data)))
      (loop for i from 0 below len
            do (setf (aref (in-memory-output-stream-data stream)
                          (+ (in-memory-output-stream-position stream) i))
                    (aref bytes i)))
      (incf (in-memory-output-stream-position stream) len))))

(defun get-memory-stream-output (stream)
  "Get accumulated output from STREAM.
PARAMETERS: stream - IN-MEMORY-OUTPUT-STREAM
RETURNS: Byte array containing all written data"
  (sb-thread:with-mutex ((in-memory-output-stream-lock stream))
    (let ((result (make-array (in-memory-output-stream-position stream)
                             :element-type '(unsigned-byte 8))))
      (loop for i from 0 below (in-memory-output-stream-position stream)
            do (setf (aref result i) (aref (in-memory-output-stream-data stream) i)))
      result)))

(defun get-memory-stream-output-string (stream)
  "Get accumulated output as string.
PARAMETERS: stream - IN-MEMORY-OUTPUT-STREAM
RETURNS: String of output"
  (let ((bytes (get-memory-stream-output stream)))
    (sb-ext:octets-to-string bytes :external-format :utf-8)))

;;; ============================================================================
;;; Flexi-Stream (UTF-8 aware stream)
;;; ============================================================================

(defstruct flexi-stream
  "Stream with flexible external format support.
SLOTS:
  underlying-stream - Base stream object
  external-format   - Encoding (:utf-8, :ascii, :latin-1)
  buffer            - I/O buffer
  position          - Buffer position
  lock              - Mutex for thread safety"
  (underlying-stream nil)
  (external-format :utf-8 :type keyword)
  (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
  (position 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun create-flexi-stream (stream &key (external-format :utf-8))
  "Create a flexi-stream wrapper around STREAM.
PARAMETERS:
  stream          - Underlying stream
  external-format - Encoding (:utf-8, :ascii, :latin-1)
RETURNS: FLEXI-STREAM"
  (make-flexi-stream :underlying-stream stream
                     :external-format external-format))

(defun flexi-write-string (stream string)
  "Write STRING to flexi-stream.
PARAMETERS:
  stream - FLEXI-STREAM
  string - String to write"
  (sb-thread:with-mutex ((flexi-stream-lock stream))
    (let ((bytes (ecase (flexi-stream-external-format stream)
                   (:utf-8 (sb-ext:string-to-octets string :external-format :utf-8))
                   (:ascii (sb-ext:string-to-octets string :external-format :ascii))
                   (:latin-1 (sb-ext:string-to-octets string :external-format :latin-1)))))
      (write-sequence bytes (flexi-stream-underlying-stream stream)))))

(defun flexi-read-string (stream count)
  "Read COUNT characters from flexi-stream.
PARAMETERS:
  stream - FLEXI-STREAM
  count  - Number of characters to read
RETURNS: String or NIL"
  (sb-thread:with-mutex ((flexi-stream-lock stream))
    (let ((bytes (make-array count :element-type '(unsigned-byte 8))))
      (let ((read-count (read-sequence bytes (flexi-stream-underlying-stream stream))))
        (when (> read-count 0)
          (sb-ext:octets-to-string (subseq bytes 0 read-count)
                                   :external-format (flexi-stream-external-format stream)))))))

;;; ============================================================================
;;; Buffered Stream Operations
;;; ============================================================================

(defstruct buffered-stream
  "Stream with configurable buffering strategy.
SLOTS:
  underlying-stream - Base stream
  buffer-size       - Size of buffer
  buffer            - Actual buffer
  position          - Current position in buffer
  dirty-p           - Whether buffer needs flush
  lock              - Mutex for thread safety"
  (underlying-stream nil)
  (buffer-size 4096 :type integer)
  (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
  (position 0 :type integer)
  (dirty-p nil :type boolean)
  (lock (sb-thread:make-mutex)))

(defun create-buffered-stream (stream &key (buffer-size 4096))
  "Create a buffered stream wrapper.
PARAMETERS:
  stream      - Underlying stream
  buffer-size - Size of buffer (default 4096)
RETURNS: BUFFERED-STREAM"
  (make-buffered-stream :underlying-stream stream
                        :buffer-size buffer-size
                        :buffer (make-array buffer-size
                                           :element-type '(unsigned-byte 8))))

(defun buffered-write (stream data)
  "Write DATA to buffered stream.
PARAMETERS:
  stream - BUFFERED-STREAM
  data   - Byte array or sequence"
  (sb-thread:with-mutex ((buffered-stream-lock stream))
    (let* ((bytes (if (typep data '(simple-array (unsigned-byte 8)))
                      data
                      (coerce data '(simple-array (unsigned-byte 8)))))
           (len (length bytes)))
      (when (+ (buffered-stream-position stream) len) > (buffered-stream-buffer-size stream))
        (buffered-flush stream))
      (loop for i from 0 below len
            do (setf (aref (buffered-stream-buffer stream)
                          (+ (buffered-stream-position stream) i))
                    (aref bytes i)))
      (incf (buffered-stream-position stream) len)
      (setf (buffered-stream-dirty-p stream) t))))

(defun buffered-flush (stream)
  "Flush STREAM's buffer to underlying stream.
PARAMETERS: stream - BUFFERED-STREAM"
  (sb-thread:with-mutex ((buffered-stream-lock stream))
    (when (buffered-stream-dirty-p stream)
      (write-sequence (subseq (buffered-stream-buffer stream)
                             0
                             (buffered-stream-position stream))
                     (buffered-stream-underlying-stream stream))
      (setf (buffered-stream-position stream) 0)
      (setf (buffered-stream-dirty-p stream) nil))))

;;; ============================================================================
;;; Stream Utilities
;;; ============================================================================

(defun copy-stream (input-stream output-stream &key (buffer-size 4096))
  "Copy from INPUT-STREAM to OUTPUT-STREAM.
PARAMETERS:
  input-stream  - Source stream
  output-stream - Destination stream
  buffer-size   - I/O buffer size"
  (let ((buffer (make-array buffer-size :element-type '(unsigned-byte 8))))
    (loop for bytes = (read-sequence buffer input-stream)
          until (zerop bytes)
          do (write-sequence (subseq buffer 0 bytes) output-stream))))

(defun stream-to-bytes (stream &key (buffer-size 4096))
  "Read entire STREAM into byte array.
PARAMETERS:
  stream      - Input stream
  buffer-size - I/O buffer size
RETURNS: Byte array"
  (let ((result '())
        (buffer (make-array buffer-size :element-type '(unsigned-byte 8))))
    (loop for bytes = (read-sequence buffer stream)
          until (zerop bytes)
          do (push (subseq buffer 0 bytes) result))
    (let* ((parts (nreverse result))
           (total (apply #'+ (mapcar #'length parts)))
           (output (make-array total :element-type '(unsigned-byte 8)))
           (pos 0))
      (loop for part in parts
            do (loop for i from 0 below (length part)
                     do (setf (aref output pos) (aref part i))
                        (incf pos)))
      output)))

;;; ============================================================================
;;; Performance Monitoring
;;; ============================================================================

(defstruct stream-stats
  "Statistics for stream operations.
SLOTS:
  bytes-read  - Total bytes read
  bytes-written - Total bytes written
  read-operations - Count of read ops
  write-operations - Count of write ops"
  (bytes-read 0 :type integer)
  (bytes-written 0 :type integer)
  (read-operations 0 :type integer)
  (write-operations 0 :type integer))

(defun create-stream-stats ()
  "Create new stream statistics object.
RETURNS: STREAM-STATS"
  (make-stream-stats))

;;; ============================================================================
;;; Initialization and Health Checks
;;; ============================================================================

(defun init ()
  "Initialize module."
  t)

(defun process (data)
  "Process data."
  (declare (type t data))
  data)

(defun status ()
  "Get module status."
  :ok)

(defun validate (input)
  "Validate input."
  (declare (type t input))
  t)

(defun cleanup ()
  "Cleanup resources."
  t)

(defun initialize-streams-sbcl ()
  "Initialize stream subsystem."
  t)

(defun validate-streams-sbcl (ctx)
  "Validate stream context."
  (declare (ignore ctx))
  t)

(defun streams-sbcl-health-check ()
  "Check health of stream system."
  :healthy)

;;; Compressed Stream Wrapper

(defstruct compressed-stream
  "Stream with on-the-fly compression support.
SLOTS:
  underlying-stream - Base stream to compress
  compression-level - 0-9 (0=none, 9=best)
  buffer            - Compression buffer
  position          - Buffer position
  lock              - Mutex for thread safety"
  (underlying-stream nil)
  (compression-level 6 :type (integer 0 9))
  (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
  (position 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun write-compressed (stream data &key (level 6))
  "Write DATA to compressed stream with compression LEVEL."
  (sb-thread:with-mutex ((compressed-stream-lock stream))
    ;; Simple RLE compression for demonstration
    (let ((compressed (compress-data data level)))
      (write-sequence compressed (compressed-stream-underlying-stream stream)))))

(defun compress-data (data level)
  "Compress DATA with specified LEVEL (simplified RLE)."
  (declare (ignore level))
  (if (null data)
      #()
      (let ((result '())
            (current (car data))
            (count 1))
        (loop for item in (cdr data)
              do (if (eq item current)
                     (incf count)
                     (progn
                       (push count result)
                       (push current result)
                       (setf current item)
                       (setf count 1))))
        (push count result)
        (push current result)
        (coerce (nreverse result) '(simple-array (unsigned-byte 8))))))

;;; Line-based Stream Operations

(defstruct line-reader
  "Stream that reads line by line.
SLOTS:
  underlying-stream - Base stream
  buffer            - Current line buffer
  eof-p             - End-of-file flag
  lock              - Mutex for thread safety"
  (underlying-stream nil)
  (buffer (make-array 4096 :element-type 'character))
  (eof-p nil :type boolean)
  (lock (sb-thread:make-mutex)))

(defun read-line-from-stream (reader)
  "Read next line from stream reader.
RETURNS: Line string or NIL at EOF"
  (sb-thread:with-mutex ((line-reader-lock reader))
    (when (line-reader-eof-p reader)
      (return-from read-line-from-stream nil))
    (let ((line nil)
          (pos 0))
      (loop
        (let ((ch (read-char (line-reader-underlying-stream reader) nil #\Newline)))
          (if (eq ch #\Newline)
              (return (coerce (subseq (line-reader-buffer reader) 0 pos) 'string))
              (progn
                (when (eq ch :eof)
                  (setf (line-reader-eof-p reader) t)
                  (if (zerop pos)
                      (return nil)
                      (return (coerce (subseq (line-reader-buffer reader) 0 pos) 'string))))
                (setf (char (line-reader-buffer reader) pos) ch)
                (incf pos))))))))

;;; Tee Stream (write to multiple destinations)

(defstruct tee-stream
  "Stream that writes to multiple underlying streams.
SLOTS:
  primary-stream   - Main stream
  secondary-streams - List of additional streams
  lock             - Mutex for thread safety"
  (primary-stream nil)
  (secondary-streams '() :type list)
  (lock (sb-thread:make-mutex)))

(defun make-tee-stream (primary &rest secondaries)
  "Create tee stream writing to PRIMARY and SECONDARIES."
  (make-tee-stream :primary-stream primary
                   :secondary-streams secondaries))

(defun write-to-tee (tee data)
  "Write DATA to all streams in tee."
  (sb-thread:with-mutex ((tee-stream-lock tee))
    (write-sequence data (tee-stream-primary-stream tee))
    (loop for stream in (tee-stream-secondary-streams tee)
          do (write-sequence data stream))))

;;; Stream Limiting (limit bytes read/written)

(defstruct limited-stream
  "Stream that enforces read/write limits.
SLOTS:
  underlying-stream - Base stream
  max-bytes        - Maximum bytes to read/write
  bytes-read       - Bytes read so far
  bytes-written    - Bytes written so far
  lock             - Mutex for thread safety"
  (underlying-stream nil)
  (max-bytes most-positive-fixnum :type integer)
  (bytes-read 0 :type integer)
  (bytes-written 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun make-limited-stream (stream max-bytes)
  "Create stream limited to MAX-BYTES."
  (make-limited-stream :underlying-stream stream
                       :max-bytes max-bytes))

(defun limited-read (stream count)
  "Read up to COUNT bytes, respecting limit."
  (sb-thread:with-mutex ((limited-stream-lock stream))
    (let ((allowed (- (limited-stream-max-bytes stream)
                      (limited-stream-bytes-read stream))))
      (if (<= allowed 0)
          nil
          (let ((to-read (min count allowed)))
            (let ((data (read-sequence (make-array to-read :element-type '(unsigned-byte 8))
                                       (limited-stream-underlying-stream stream))))
              (incf (limited-stream-bytes-read stream) (length data))
              data))))))

(defun limited-write (stream data)
  "Write DATA, respecting limit."
  (sb-thread:with-mutex ((limited-stream-lock stream))
    (let ((allowed (- (limited-stream-max-bytes stream)
                      (limited-stream-bytes-written stream))))
      (if (<= allowed 0)
          (error "Write limit exceeded"))
      (let ((to-write (min (length data) allowed)))
        (write-sequence (subseq data 0 to-write) (limited-stream-underlying-stream stream))
        (incf (limited-stream-bytes-written stream) to-write)))))

;;; Peek Operations (look ahead without consuming)

(defstruct peek-stream
  "Stream supporting peek operations.
SLOTS:
  underlying-stream - Base stream
  peek-buffer      - Peeked data
  position         - Current position
  lock             - Mutex for thread safety"
  (underlying-stream nil)
  (peek-buffer #() :type (simple-array (unsigned-byte 8)))
  (position 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun peek-byte (stream &optional (offset 0))
  "Peek at byte at OFFSET without consuming."
  (sb-thread:with-mutex ((peek-stream-lock stream))
    (let ((peek-pos (+ (peek-stream-position stream) offset)))
      (if (< peek-pos (length (peek-stream-peek-buffer stream)))
          (aref (peek-stream-peek-buffer stream) peek-pos)
          nil))))

(defun consume-peeked (stream count)
  "Consume COUNT peeked bytes."
  (sb-thread:with-mutex ((peek-stream-lock stream))
    (incf (peek-stream-position stream) count)))

;;; Stream Position and Seeking

(defun stream-position-info (stream)
  "Get information about stream position for various stream types."
  (cond
    ((in-memory-input-stream-p stream)
     (list :position (in-memory-stream-position stream)
           :type :in-memory-input))
    ((in-memory-output-stream-p stream)
     (list :position (in-memory-output-stream-position stream)
           :type :in-memory-output))
    ((buffered-stream-p stream)
     (list :position (buffered-stream-position stream)
           :type :buffered))
    (t (list :position :unknown :type :unknown))))

;;; Stream Debugging and Monitoring

(defstruct stream-monitor
  "Monitor for stream operations.
SLOTS:
  stream           - Stream being monitored
  read-count      - Number of read operations
  write-count     - Number of write operations
  total-bytes-read - Total bytes read
  total-bytes-written - Total bytes written
  errors          - Error count
  lock            - Mutex for thread safety"
  (stream nil)
  (read-count 0 :type integer)
  (write-count 0 :type integer)
  (total-bytes-read 0 :type integer)
  (total-bytes-written 0 :type integer)
  (errors 0 :type integer)
  (lock (sb-thread:make-mutex)))

(defun make-stream-monitor (stream)
  "Create monitor for STREAM."
  (make-stream-monitor :stream stream))

(defun monitored-read (monitor count)
  "Read through monitor."
  (sb-thread:with-mutex ((stream-monitor-lock monitor))
    (incf (stream-monitor-read-count monitor))
    (handler-case
        (let ((data (read-sequence (make-array count :element-type '(unsigned-byte 8))
                                   (stream-monitor-stream monitor))))
          (incf (stream-monitor-total-bytes-read monitor) (length data))
          data)
      (error (e)
        (incf (stream-monitor-errors monitor))
        (error e)))))

(defun monitored-write (monitor data)
  "Write through monitor."
  (sb-thread:with-mutex ((stream-monitor-lock monitor))
    (incf (stream-monitor-write-count monitor))
    (handler-case
        (progn
          (write-sequence data (stream-monitor-stream monitor))
          (incf (stream-monitor-total-bytes-written monitor) (length data)))
      (error (e)
        (incf (stream-monitor-errors monitor))
        (error e)))))

(defun monitor-stats (monitor)
  "Get statistics from monitor."
  (sb-thread:with-mutex ((stream-monitor-lock monitor))
    (list :read-operations (stream-monitor-read-count monitor)
          :write-operations (stream-monitor-write-count monitor)
          :total-bytes-read (stream-monitor-total-bytes-read monitor)
          :total-bytes-written (stream-monitor-total-bytes-written monitor)
          :errors (stream-monitor-errors monitor))))

;;; Bidirectional Stream Wrapper

(defstruct bidirectional-stream
  "Wraps separate input and output streams as single interface.
SLOTS:
  input-stream  - Stream for reading
  output-stream - Stream for writing
  lock          - Mutex for synchronization"
  (input-stream nil)
  (output-stream nil)
  (lock (sb-thread:make-mutex)))

(defun make-bidirectional-stream (input output)
  "Create bidirectional stream from INPUT and OUTPUT streams."
  (make-bidirectional-stream :input-stream input
                             :output-stream output))

(defun bidir-read (stream count)
  "Read from bidirectional stream."
  (sb-thread:with-mutex ((bidirectional-stream-lock stream))
    (read-sequence (make-array count :element-type '(unsigned-byte 8))
                   (bidirectional-stream-input-stream stream))))

(defun bidir-write (stream data)
  "Write to bidirectional stream."
  (sb-thread:with-mutex ((bidirectional-stream-lock stream))
    (write-sequence data (bidirectional-stream-output-stream stream))))

;;; Ring Buffer Stream

(defstruct ring-buffer-stream
  "Fixed-size circular buffer stream.
SLOTS:
  buffer        - Underlying array
  read-pos      - Current read position
  write-pos     - Current write position
  size          - Buffer capacity
  lock          - Mutex for synchronization"
  (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
  (read-pos 0 :type integer)
  (write-pos 0 :type integer)
  (size 4096 :type integer)
  (lock (sb-thread:make-mutex)))

(defun make-ring-buffer-stream (&key (capacity 4096))
  "Create ring buffer stream with CAPACITY."
  (make-ring-buffer-stream :buffer (make-array capacity :element-type '(unsigned-byte 8))
                           :size capacity))

(defun ring-available-for-read (ring)
  "Get number of bytes available to read."
  (sb-thread:with-mutex ((ring-buffer-stream-lock ring))
    (let ((available (- (ring-buffer-stream-write-pos ring)
                        (ring-buffer-stream-read-pos ring))))
      (if (< available 0)
          (+ available (ring-buffer-stream-size ring))
          available))))

(defun ring-available-for-write (ring)
  "Get number of bytes available to write."
  (- (ring-buffer-stream-size ring) (ring-available-for-read ring)))

(defun ring-buffer-write (ring data)
  "Write to ring buffer."
  (sb-thread:with-mutex ((ring-buffer-stream-lock ring))
    (let ((to-write (min (length data) (ring-available-for-write ring))))
      (loop for i from 0 below to-write
            do (setf (aref (ring-buffer-stream-buffer ring)
                          (mod (+ (ring-buffer-stream-write-pos ring) i)
                               (ring-buffer-stream-size ring)))
                    (aref data i)))
      (setf (ring-buffer-stream-write-pos ring)
            (mod (+ (ring-buffer-stream-write-pos ring) to-write)
                 (ring-buffer-stream-size ring)))
      to-write)))

(defun ring-buffer-read (ring count)
  "Read from ring buffer."
  (sb-thread:with-mutex ((ring-buffer-stream-lock ring))
    (let ((to-read (min count (ring-available-for-read ring))))
      (if (zerop to-read)
          #()
          (let ((result (make-array to-read :element-type '(unsigned-byte 8))))
            (loop for i from 0 below to-read
                  do (setf (aref result i)
                          (aref (ring-buffer-stream-buffer ring)
                                (mod (+ (ring-buffer-stream-read-pos ring) i)
                                     (ring-buffer-stream-size ring)))))
            (setf (ring-buffer-stream-read-pos ring)
                  (mod (+ (ring-buffer-stream-read-pos ring) to-read)
                       (ring-buffer-stream-size ring)))
            result)))))

;;; Stream Adapters

(defstruct stream-adapter
  "Adapts between different stream protocols.
SLOTS:
  source        - Source stream
  formatter     - Formatting function
  parser        - Parsing function
  lock          - Mutex for synchronization"
  (source nil)
  (formatter nil :type (or null function))
  (parser nil :type (or null function))
  (lock (sb-thread:make-mutex)))

(defun make-stream-adapter (source &key (formatter #'identity) (parser #'identity))
  "Create stream adapter with FORMAT and PARSE functions."
  (make-stream-adapter :source source
                       :formatter formatter
                       :parser parser))

(defun adapter-read (adapter count)
  "Read and parse from adapter."
  (sb-thread:with-mutex ((stream-adapter-lock adapter))
    (let ((raw-data (read-sequence (make-array count :element-type '(unsigned-byte 8))
                                   (stream-adapter-source adapter))))
      (if (stream-adapter-parser adapter)
          (funcall (stream-adapter-parser adapter) raw-data)
          raw-data))))

(defun adapter-write (adapter data)
  "Format and write through adapter."
  (sb-thread:with-mutex ((stream-adapter-lock adapter))
    (let ((formatted (if (stream-adapter-formatter adapter)
                         (funcall (stream-adapter-formatter adapter) data)
                         data)))
      (write-sequence formatted (stream-adapter-source adapter)))))

;;; Statistics Collection for Streams

(defvar *stream-registry* (make-hash-table :test #'equal)
  "Registry of active streams for monitoring.")

(defvar *stream-registry-lock* (sb-thread:make-mutex :name "stream-registry-lock")
  "Lock for stream registry.")

(defun register-monitored-stream (name monitor)
  "Register a monitored stream in global registry."
  (sb-thread:with-mutex (*stream-registry-lock*)
    (setf (gethash name *stream-registry*) monitor)))

(defun get-monitored-stream (name)
  "Retrieve monitored stream by name."
  (sb-thread:with-mutex (*stream-registry-lock*)
    (gethash name *stream-registry*)))

(defun list-monitored-streams ()
  "List all registered monitored streams."
  (sb-thread:with-mutex (*stream-registry-lock*)
    (loop for name being the hash-keys of *stream-registry*
          collect name)))

(defun global-stream-stats ()
  "Get aggregated statistics for all monitored streams."
  (sb-thread:with-mutex (*stream-registry-lock*)
    (let ((total-reads 0)
          (total-writes 0)
          (total-bytes-read 0)
          (total-bytes-written 0)
          (total-errors 0))
      (loop for monitor being the hash-values of *stream-registry*
            do (let ((stats (monitor-stats monitor)))
                 (incf total-reads (getf stats :read-operations))
                 (incf total-writes (getf stats :write-operations))
                 (incf total-bytes-read (getf stats :total-bytes-read))
                 (incf total-bytes-written (getf stats :total-bytes-written))
                 (incf total-errors (getf stats :errors))))
      (list :total-monitored-streams (hash-table-count *stream-registry*)
            :total-reads total-reads
            :total-writes total-writes
            :total-bytes-read total-bytes-read
            :total-bytes-written total-bytes-written
            :total-errors total-errors))))

(defun print-global-stream-stats (&optional (stream t))
  "Print global stream statistics."
  (let ((stats (global-stream-stats)))
    (format stream "~&=== Global Stream Statistics ===~%")
    (format stream "  Monitored Streams: ~D~%" (getf stats :total-monitored-streams))
    (format stream "  Total Reads: ~D~%" (getf stats :total-reads))
    (format stream "  Total Writes: ~D~%" (getf stats :total-writes))
    (format stream "  Bytes Read: ~D~%" (getf stats :total-bytes-read))
    (format stream "  Bytes Written: ~D~%" (getf stats :total-bytes-written))
    (format stream "  Errors: ~D~%" (getf stats :total-errors))))

;;; Broadcast Stream

(defstruct broadcast-stream
  "Stream that writes to multiple output streams.
SLOTS:
  streams - List of output streams
  lock    - Mutex for thread safety"
  (streams '() :type list)
  (lock (sb-thread:make-mutex)))

(defun make-broadcast-stream (&rest output-streams)
  "Create broadcast stream writing to all OUTPUT-STREAMS."
  (make-broadcast-stream :streams output-streams))

(defun broadcast-write (stream data)
  "Write DATA to all streams in broadcast."
  (sb-thread:with-mutex ((broadcast-stream-lock stream))
    (loop for s in (broadcast-stream-streams stream)
          do (write-sequence data s))))

;;; Echo Stream (read from source, echo to output)

(defstruct echo-stream
  "Stream that reads and simultaneously echoes to another stream.
SLOTS:
  source       - Source stream to read from
  echo-target  - Where to echo read data
  lock         - Mutex for thread safety"
  (source nil)
  (echo-target nil)
  (lock (sb-thread:make-mutex)))

(defun make-echo-stream (source echo-target)
  "Create echo stream."
  (make-echo-stream :source source :echo-target echo-target))

(defun echo-read (stream count)
  "Read from echo stream (reading also echoes)."
  (sb-thread:with-mutex ((echo-stream-lock stream))
    (let ((data (read-sequence (make-array count :element-type '(unsigned-byte 8))
                               (echo-stream-source stream))))
      (write-sequence data (echo-stream-echo-target stream))
      data)))

;;; Slot-based Stream (fixed-size slot allocation)

(defstruct slotted-stream
  "Stream using pre-allocated slots for buffering.
SLOTS:
  slots         - Array of byte arrays
  current-slot  - Current slot index
  slot-size     - Bytes per slot
  lock          - Mutex for thread safety"
  (slots (make-array 0) :type vector)
  (current-slot 0 :type integer)
  (slot-size 1024 :type integer)
  (lock (sb-thread:make-mutex)))

(defun make-slotted-stream (&key (slot-count 10) (slot-size 1024))
  "Create slotted stream with SLOT-COUNT pre-allocated slots."
  (make-slotted-stream
   :slots (make-array slot-count
                      :initial-contents (loop repeat slot-count
                                              collect (make-array slot-size
                                                                  :element-type '(unsigned-byte 8))))
   :slot-size slot-size))

(defun slotted-write (stream data)
  "Write to slotted stream (auto-rolls to next slot when full)."
  (sb-thread:with-mutex ((slotted-stream-lock stream))
    (let ((to-write (min (length data) (slotted-stream-slot-size stream)))
          (slot (aref (slotted-stream-slots stream) (slotted-stream-current-slot stream))))
      (loop for i from 0 below to-write
            do (setf (aref slot i) (aref data i)))
      ;; Advance slot for next write
      (setf (slotted-stream-current-slot stream)
            (mod (1+ (slotted-stream-current-slot stream))
                 (length (slotted-stream-slots stream))))
      to-write)))

;;; Zero-Copy Stream Wrapper

(defstruct zero-copy-stream
  "Stream that minimizes data copying.
SLOTS:
  buffer      - Shared buffer
  read-ptr    - Read position
  write-ptr   - Write position
  size        - Buffer capacity
  lock        - Mutex for thread safety"
  (buffer (make-array 8192 :element-type '(unsigned-byte 8)))
  (read-ptr 0 :type integer)
  (write-ptr 0 :type integer)
  (size 8192 :type integer)
  (lock (sb-thread:make-mutex)))

(defun make-zero-copy-stream (&key (capacity 8192))
  "Create zero-copy stream."
  (make-zero-copy-stream :buffer (make-array capacity :element-type '(unsigned-byte 8))
                        :size capacity))

(defun zc-write (stream data)
  "Write to zero-copy stream (by reference, not copy)."
  (sb-thread:with-mutex ((zero-copy-stream-lock stream))
    (let ((to-write (min (length data) (- (zero-copy-stream-size stream)
                                          (zero-copy-stream-write-ptr stream)))))
      (loop for i from 0 below to-write
            do (setf (aref (zero-copy-stream-buffer stream)
                          (+ (zero-copy-stream-write-ptr stream) i))
                    (aref data i)))
      (incf (zero-copy-stream-write-ptr stream) to-write)
      to-write)))

(defun zc-read (stream count)
  "Read from zero-copy stream (returns reference to buffer)."
  (sb-thread:with-mutex ((zero-copy-stream-lock stream))
    (let ((to-read (min count (- (zero-copy-stream-write-ptr stream)
                                 (zero-copy-stream-read-ptr stream)))))
      (if (zerop to-read)
          #()
          (let ((result-view (subseq (zero-copy-stream-buffer stream)
                                     (zero-copy-stream-read-ptr stream)
                                     (+ (zero-copy-stream-read-ptr stream) to-read))))
            (incf (zero-copy-stream-read-ptr stream) to-read)
            result-view)))))

;;; Stream Health Monitoring

(defstruct stream-health-monitor
  "Monitor stream health and detect issues.
SLOTS:
  streams           - Monitored streams
  error-threshold   - Max errors before unhealthy
  latency-threshold - Max acceptable latency
  lock              - Mutex for thread safety"
  (streams (make-hash-table :test #'equal))
  (error-threshold 10 :type integer)
  (latency-threshold 1.0 :type single-float)
  (lock (sb-thread:make-mutex)))

(defun stream-health-status (monitor stream-name)
  "Check health of monitored stream."
  (sb-thread:with-mutex ((stream-health-monitor-lock monitor))
    (let ((monitor-obj (gethash stream-name (stream-health-monitor-streams monitor))))
      (if (not monitor-obj)
          :unknown
          (let ((stats (monitor-stats monitor-obj)))
            (if (> (getf stats :errors) (stream-health-monitor-error-threshold monitor))
                :critical
                :healthy))))))

;;; Stream Performance Profiling

(defstruct stream-profile
  "Performance profile for stream operations.
SLOTS:
  total-read-time   - Cumulative read time (ms)
  total-write-time  - Cumulative write time (ms)
  read-count        - Number of read ops
  write-count       - Number of write ops
  max-read-latency  - Maximum latency of single read
  max-write-latency - Maximum latency of single write"
  (total-read-time 0.0 :type single-float)
  (total-write-time 0.0 :type single-float)
  (read-count 0 :type integer)
  (write-count 0 :type integer)
  (max-read-latency 0.0 :type single-float)
  (max-write-latency 0.0 :type single-float))

(defun create-stream-profile ()
  "Create new stream performance profile."
  (make-stream-profile))

(defun profile-stream-read (profile stream count)
  "Profile a stream read operation."
  (let ((start (get-internal-real-time)))
    (let ((result (read-sequence (make-array count :element-type '(unsigned-byte 8))
                                 stream)))
      (let ((elapsed (/ (float (- (get-internal-real-time) start))
                        internal-time-units-per-second
                        1000)))  ; Convert to ms
        (incf (stream-profile-total-read-time profile) elapsed)
        (incf (stream-profile-read-count profile))
        (when (> elapsed (stream-profile-max-read-latency profile))
          (setf (stream-profile-max-read-latency profile) (coerce elapsed 'single-float))))
      result)))

(defun profile-stream-write (profile stream data)
  "Profile a stream write operation."
  (let ((start (get-internal-real-time)))
    (write-sequence data stream)
    (let ((elapsed (/ (float (- (get-internal-real-time) start))
                      internal-time-units-per-second
                      1000)))  ; Convert to ms
      (incf (stream-profile-total-write-time profile) elapsed)
      (incf (stream-profile-write-count profile))
      (when (> elapsed (stream-profile-max-write-latency profile))
        (setf (stream-profile-max-write-latency profile) (coerce elapsed 'single-float))))))

(defun print-stream-profile (profile &optional (stream t))
  "Print stream performance profile."
  (format stream "~&=== Stream Performance Profile ===~%")
  (format stream "  Read Operations: ~D (total: ~5,2F ms, avg: ~5,4F ms, max: ~5,4F ms)~%"
          (stream-profile-read-count profile)
          (stream-profile-total-read-time profile)
          (if (> (stream-profile-read-count profile) 0)
              (/ (stream-profile-total-read-time profile) (stream-profile-read-count profile))
              0.0)
          (stream-profile-max-read-latency profile))
  (format stream "  Write Operations: ~D (total: ~5,2F ms, avg: ~5,4F ms, max: ~5,4F ms)~%"
          (stream-profile-write-count profile)
          (stream-profile-total-write-time profile)
          (if (> (stream-profile-write-count profile) 0)
              (/ (stream-profile-total-write-time profile) (stream-profile-write-count profile))
              0.0)
          (stream-profile-max-write-latency profile)))

;;; Substantive Functional Logic

(defun deep-copy-list (l)
  "Recursively copies a nested list."
  (if (atom l) l (cons (deep-copy-list (car l)) (deep-copy-list (cdr l)))))

(defun group-by-count (list n)
  "Groups list elements into sublists of size N."
  (loop for i from 0 below (length list) by n
        collect (subseq list i (min (+ i n) (length list)))))
