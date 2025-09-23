;;;; lisp-mcp-server.asd

(asdf:defsystem "lisp-mcp-server"
  :description "Model Context Protocol server for Common Lisp (MVP skeleton)"
  :author ""
  :license "MIT"
  :version "0.1.0"
  :depends-on (
    :alexandria
    :yason
    :usocket
    :bordeaux-threads
    :trivial-backtrace
    )
  :serial t
  :components (
    (:module "src"
     :components (
       (:file "package")
       (:file "log")
       (:file "repl")
       (:file "protocol")
       (:file "tcp")
       (:file "core")
       (:file "run")))
    ))

(asdf:defsystem "lisp-mcp-server/tests"
  :description "Tests for lisp-mcp-server"
  :author ""
  :license "MIT"
  :depends-on ("lisp-mcp-server" :rove :usocket :bordeaux-threads :cl-ppcre)
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "core-test")
                             (:file "repl-test")
                             (:file "protocol-test")
                             (:file "logging-test")
                             (:file "tools-test")
                             (:file "error-test")
                             (:file "tcp-test")
                             (:file "bridge-test"))))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :rove :run c)))
