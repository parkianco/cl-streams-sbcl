# cl-streams-sbcl

Flexible binary/character streams for SBCL with ZERO external dependencies.

## Installation

```lisp
(asdf:load-system :cl-streams-sbcl)
```

## API

### Input Streams
- `make-in-memory-input-stream` - Create stream from byte sequence
- `with-input-from-sequence` - Read from byte sequence

### Output Streams
- `make-in-memory-output-stream` - Create accumulating output stream
- `get-output-stream-sequence` - Get accumulated bytes
- `with-output-to-sequence` - Capture output to byte vector

### Flexible Streams
- `make-flexi-stream` - Wrap stream with encoding support
- `flexi-stream-external-format` - Get/set encoding

## Example

```lisp
;; Read from bytes
(with-input-from-sequence (s #(72 101 108 108 111))
  (read-line s)) ; => "Hello"

;; Write to bytes
(with-output-to-sequence (s)
  (write-string "Hello" s)) ; => #(72 101 108 108 111)
```

## License

BSD-3-Clause. Copyright (c) 2024-2026 Parkian Company LLC.
