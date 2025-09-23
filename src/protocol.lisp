;;;; src/protocol.lisp
(in-package :lisp-mcp-server)

(defparameter +protocol-version+ "2025-06-18")
(defparameter +supported-protocol-versions+
  '("2025-06-18" "2025-03-26" "2024-11-05")
  "Supported MCP protocol versions, ordered by preference.")

(defclass server-state ()
  ((initialized-p :initform nil :accessor initialized-p)
   (client-info  :initform nil :accessor client-info)))

(defun make-state () (make-instance 'server-state))

(defun %decode-json (line)
  (yason:parse line))

(defun %encode-json (obj)
  (yason:with-output-to-string* ()
    (yason:encode obj)))

(defun %make-ht (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun %result (id payload)
  (%make-ht "jsonrpc" "2.0" "id" id "result" payload))

(defun %error (id code message &optional data)
  (let* ((err (%make-ht "code" code "message" message))
         (obj (%make-ht "jsonrpc" "2.0" "id" id "error" err)))
    (when data (setf (gethash "data" err) data))
    obj))

(defun handle-initialize (state id params)
  (declare (ignore state))
  (let* ((client-ver (and params (gethash "protocolVersion" params)))
         (chosen (if (and client-ver (find client-ver +supported-protocol-versions+
                                           :test #'string=))
                     client-ver
                     (first +supported-protocol-versions+)))
         (caps (%make-ht
                "tools" (%make-ht "listChanged" t))))
    (%result id
             (%make-ht
              "protocolVersion" chosen
              "serverInfo" (%make-ht "name" "lisp-mcp-server" "version" (version))
              "capabilities" caps))))

(defun handle-notification (state method params)
  (declare (ignore state params))
  (when (string= method "notifications/initialized")
    (return-from handle-notification nil))
  nil)

(defun tools-descriptor-repl ()
  (%make-ht
   "name" "repl-eval"
   "description" "Evaluate Common Lisp forms and return the last value as printed text."
   "inputSchema" (%make-ht
                  "type" "object"
                  "properties" (let ((p (make-hash-table :test #'equal)))
                                 (setf (gethash "code" p)
                                       (%make-ht "type" "string" "description" "Code string of one or more forms"))
                                 (setf (gethash "package" p) (%make-ht "type" "string"))
                                 (setf (gethash "printLevel" p) (%make-ht "type" "integer"))
                                 (setf (gethash "printLength" p) (%make-ht "type" "integer"))
                                 p))))

(defun handle-tools-list (id)
  (let* ((tools (vector (tools-descriptor-repl))))
    (%result id (%make-ht "tools" tools))))

(defun %normalize-tool-name (name)
  "Normalize a tool NAME possibly namespaced like 'ns.tool' or 'ns/tool'.
Returns a downcased local tool name (string)."
  (let* ((s (string-downcase name))
         (dot (position #\. s :from-end t))
         (sl (position #\/ s :from-end t))
         (idx (max (or dot -1) (or sl -1))))
    (subseq s (1+ idx))))

(defun handle-tools-call (id params)
  (let* ((name (and params (gethash "name" params)))
         (args (and params (gethash "arguments" params)))
         (local (and name (%normalize-tool-name name))))
    (when name (log-event :debug "tools.call" "name" name "local" local))
    (cond
      ((member local '("repl-eval" "repl.eval" "repl_eval") :test #'string=)
       (let* ((code (and args (gethash "code" args)))
              (pkg  (and args (gethash "package" args)))
              (pl   (and args (gethash "printLevel" args)))
              (plen (and args (gethash "printLength" args))))
         (handler-case
             (multiple-value-bind (printed _)
                 (repl-eval (or code "")
                            :package (or pkg *package*)
                            :print-level pl
                            :print-length plen)
               (declare (ignore _))
               (let* ((item (%make-ht "type" "text" "text" printed))
                      (content (make-array 1 :initial-contents (list item))))
                 (%result id (%make-ht "content" content))))
           (condition (c)
             (log-event :error "tools.error"
                        "name" (or name local)
                        "type" (condition-type-string c)
                        "message" (princ-to-string c))
             (let ((data (%make-ht
                          "tool" (or name local)
                          "type" (condition-type-string c)
                          "message" (princ-to-string c)))
                   (bt (%backtrace-string c)))
               (when bt (setf (gethash "backtrace" data) bt))
               (%error id -32000 "Tool evaluation error." data))))))
      (t
       (%error id -32601 (format nil "Tool ~A not found" name))))))

(defun handle-request (state id method params)
  (cond
    ((string= method "initialize") (handle-initialize state id params))
    ((string= method "tools/list") (handle-tools-list id))
    ((string= method "tools/call") (handle-tools-call id params))
    ((string= method "ping") (%result id (%make-ht)))
    (t (%error id -32601 (format nil "Method ~A not found" method)))))

(defun process-json-line (line &optional (state (make-state)))
  "Process one JSON-RPC line and return a JSON line to send, or NIL for notifications."
  (let* ((msg nil)
         (early-resp nil))
    (handler-case
        (setf msg (%decode-json line))
      (condition (c)
        (log-event :error "rpc.parse-error" "message" (princ-to-string c))
        (let* ((bt (%backtrace-string c))
               (data (when bt (let ((h (make-hash-table :test #'equal)))
                                (setf (gethash "backtrace" h) bt)
                                h))))
          (setf early-resp (%encode-json (%error nil -32700 "Parse error" data))))))
    (when early-resp (return-from process-json-line early-resp))
    (let* ((jsonrpc (gethash "jsonrpc" msg))
           (id (gethash "id" msg))
           (method (gethash "method" msg))
           (params (gethash "params" msg)))
      (log-event :debug "rpc.dispatch" "id" id "method" method)
      (unless (and (stringp jsonrpc) (string= jsonrpc "2.0"))
        (let ((resp (%encode-json (%error id -32600 "Invalid Request"))))
          (log-event :warn "rpc.invalid" "reason" "bad jsonrpc version")
          (return-from process-json-line resp)))
      (handler-case
          (if method
              (if id
                  (let ((r (handle-request state id method params)))
                    (log-event :debug "rpc.result" "id" id "method" method)
                    (%encode-json r))
                  ;; notification
                  (progn
                    (handle-notification state method params)
                    (log-event :debug "rpc.notify" "method" method)
                    nil))
              (let ((resp (%encode-json (%error id -32600 "Invalid Request"))))
                (log-event :warn "rpc.invalid" "reason" "missing method")
                resp))
        (condition (c)
          (log-event :error "rpc.internal" "id" id "method" method
                     "message" (princ-to-string c))
          (let ((bt (%backtrace-string c))
                (data nil))
            (when bt (let ((h (make-hash-table :test #'equal)))
                       (setf (gethash "backtrace" h) bt)
                       (setf data h)))
            (%encode-json (%error id -32603 "Internal error" data))))))))
