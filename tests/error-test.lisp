;;;; tests/error-test.lisp
(in-package :lisp-mcp-server/tests)

(deftest parse-error-returns-jsonrpc-error
  (testing "invalid JSON yields -32700 Parse error with backtrace by default"
    (let* ((resp (mcp:process-json-line "{not json}"))
           (obj (yason:parse resp))
           (err (gethash "error" obj))
           (data (and err (gethash "data" err))))
      (ok err)
      (ok (eql (gethash "code" err) -32700))
      (ok (stringp (gethash "message" err)))
      (ok data)
      (ok (stringp (gethash "backtrace" data)))
      (ok (> (length (gethash "backtrace" data)) 0)))))

(deftest repl-eval-tool-error-maps-to-jsonrpc
  (testing "repl-eval failure maps to -32000 with tool metadata and backtrace"
    (let* ((req "{\"jsonrpc\":\"2.0\",\"id\":101,\"method\":\"tools/call\",\"params\":{\"name\":\"repl-eval\",\"arguments\":{\"code\":\"(/ 1 0)\"}}}"))
      (let* ((resp (mcp:process-json-line req))
             (obj (yason:parse resp))
             (err (gethash "error" obj))
             (data (and err (gethash "data" err))))
        (ok err)
        (ok (eql (gethash "id" obj) 101))
        (ok (eql (gethash "code" err) -32000))
        (ok (stringp (gethash "message" err)))
        (ok (string= (gethash "tool" data) "repl-eval"))
        (ok (stringp (gethash "type" data)))
        (ok (stringp (gethash "backtrace" data)))
        (ok (> (length (gethash "backtrace" data)) 0)))))
  (testing "(error \"boom\") also maps to -32000 and includes backtrace"
    (let* ((req "{\"jsonrpc\":\"2.0\",\"id\":102,\"method\":\"tools/call\",\"params\":{\"name\":\"repl-eval\",\"arguments\":{\"code\":\"(error \\\"boom\\\")\"}}}"))
      (let* ((resp (mcp:process-json-line req))
             (obj (yason:parse resp))
             (err (gethash "error" obj))
             (data (and err (gethash "data" err))))
        (ok err)
        (ok (eql (gethash "id" obj) 102))
        (ok (eql (gethash "code" err) -32000))
        (ok (string= (gethash "tool" data) "repl-eval"))
        (ok (stringp (gethash "message" data)))
        (ok (stringp (gethash "backtrace" data)))))))

(deftest error-detail-policy-overrides
  (testing "when *error-detail* is :message, data/backtrace are suppressed"
    (let ((mcp::*error-detail* :message))
      (let* ((resp (mcp:process-json-line "{not json}"))
             (obj (yason:parse resp))
             (err (gethash "error" obj)))
        (ok (null (gethash "data" err))))))

  (testing "when *error-detail* is :none, data/backtrace are suppressed"
    (let ((mcp::*error-detail* :none))
      (let* ((req "{\"jsonrpc\":\"2.0\",\"id\":301,\"method\":\"tools/call\",\"params\":{\"name\":\"repl-eval\",\"arguments\":{\"code\":\"(/ 1 0)\"}}}"))
        (let* ((resp (mcp:process-json-line req))
               (obj (yason:parse resp))
               (err (gethash "error" obj)))
          (ok (null (gethash "data" err))))))))
