;;;; src/tcp.lisp
(in-package :lisp-mcp-server)

(defun %process-stream (stream)
  (let ((state (make-state)))
    (loop for line = (read-line stream nil :eof)
          until (eq line :eof)
          do (let ((resp (process-json-line line state)))
               (when resp
                 (write-line resp stream)
                 (finish-output stream))))))

(defun serve-tcp (&key (host "127.0.0.1") (port 0) (accept-once t) on-listening)
  "Serve MCP over TCP. If PORT is 0, an ephemeral port is chosen.
Calls ON-LISTENING with the actual port when ready. If ACCEPT-ONCE is T,
accepts a single connection and returns T after the client closes."
  (let ((listener nil))
    (unwind-protect
         (progn
           (setf listener (usocket:socket-listen host port :reuse-address t
                                                           :element-type 'character))
           (let ((actual (usocket:get-local-port listener)))
             (when on-listening (funcall on-listening actual)))
           (labels ((handle-one ()
                      (let ((client nil)
                            (stream nil))
                        (unwind-protect
                             (progn
                               (setf client (usocket:socket-accept listener))
                               (log-event :info "tcp.accept" "remote" (ignore-errors (usocket:get-peer-address client)))
                               (setf stream (usocket:socket-stream client))
                               (%process-stream stream)
                               t)
                          (when stream (ignore-errors (close stream)))
                          (when client (ignore-errors (usocket:socket-close client)))))))
             (if accept-once
                 (handle-one)
                 (loop do (handle-one)))))
      (when listener (ignore-errors (usocket:socket-close listener))))))
