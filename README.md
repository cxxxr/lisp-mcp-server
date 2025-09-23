# lisp-mcp-server

A minimal Model Context Protocol (MCP) server for Common Lisp. It provides a
newline‑delimited JSON‑RPC 2.0 transport over stdio or TCP, a small protocol
layer (initialize, ping, tools/list, tools/call), and a REPL tool that evaluates
forms and returns the last value.

This repo is intentionally small and test-first. It’s designed for editor/agent
clients to drive Common Lisp development via MCP.

## Features
- JSON‑RPC 2.0 request/response framing (one message per line)
- MCP initialize handshake with capability discovery
- Tools API with one built-in tool: `repl-eval`
- Transports: `:stdio` and `:tcp`
- Structured JSON logs with level control via env var
- Rove test suite wired through ASDF `test-op`

## Protocol Support
- Protocol versions recognized: `2025-06-18`, `2025-03-26`, `2024-11-05`
  - On `initialize`, if the client’s `protocolVersion` is supported it is echoed
    back; otherwise the server’s preferred version is selected.

## Requirements
- SBCL 2.x (developed with SBCL 2.5.x)
- Quicklisp (for dependencies)
- Dependencies (via ASDF/Quicklisp): `alexandria`, `yason`, `usocket`, `bordeaux-threads`, `rove` (tests)

Note: The repository currently uses `yason` for JSON.

## Quick Start
Load and run from an existing REPL:

```lisp
(ql:quickload :lisp-mcp-server)
(asdf:load-system :lisp-mcp-server)

;; Start TCP transport on an ephemeral port, print chosen port
(lisp-mcp-server:run :transport :tcp
                     :port 12345
                     :accept-once nil
                     :on-listening (lambda (p)
                                     (format t "~&port=~A~%" p)))
```

Or run a minimal stdio loop (one JSON‑RPC line per request):

```lisp
(lisp-mcp-server:run :transport :stdio)
```

### Try it with the bundled clients
- Python TCP one‑shot client (initialize):

```bash
python3 scripts/client_init.py --host 127.0.0.1 --port 12345 --method initialize --id 1
```

- Stdio↔TCP bridge (connect editor’s stdio to the TCP server):

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | \
  python3 scripts/stdio_tcp_bridge.py --host 127.0.0.1 --port 12345
```

The bridge uses a bounded connect timeout but disables read timeouts after
connecting, so it can stay idle indefinitely (until stdin closes).

## Tools
### `repl-eval`
Evaluate one or more forms and return the last value as a text item.

Input schema (JSON):
- `code` (string, required): one or more s‑expressions
- `package` (string, optional): package to evaluate in (default `CL-USER`)
- `printLevel` (integer|null): binds `*print-level*`
- `printLength` (integer|null): binds `*print-length*`

Example JSON‑RPC request:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call",
 "params":{"name":"repl-eval","arguments":{"code":"(+ 1 2)"}}}
```

Response (excerpt):

```json
{"result":{"content":[{"type":"text","text":"3"}]}}
```

## Logging
- Structured JSON line logs to `*error-output*`.
- Control level via env var `MCP_LOG_LEVEL` with one of: `debug`, `info`, `warn`, `error`.

### Error details

- By default, JSON-RPC error responses include error messages and stack traces in `error.data.backtrace`.
- You can suppress details with `MCP_ERROR_DETAIL=message` for message only, or `MCP_ERROR_DETAIL=none` for no details.
  Both settings apply to parse/internal/tool errors.
  Since backtraces contain internal information, only enable them in trusted environments.

Example:

```bash
MCP_LOG_LEVEL=debug sbcl --eval '(ql:quickload :lisp-mcp-server)' ...
```

## Running Tests
This project uses Rove and ASDF’s `test-op`.

From a REPL with Quicklisp:

```lisp
(asdf:load-asd #P"lisp-mcp-server.asd")
(asdf:test-system "lisp-mcp-server")
```

What’s covered:
- Version/API surface sanity
- REPL evaluation semantics (reader eval enabled)
- Protocol handshake (`initialize`, `ping`, tools listing/calls)
- Logging of RPC dispatch/results
- TCP server accept/respond (newline‑delimited JSON)
- Stdio↔TCP bridge stays alive on idle and exits cleanly when stdin closes

Note: Running tests compiles FASLs into `~/.cache/...`. Ensure your environment
allows writing there or configure SBCL’s cache directory accordingly.

## Project Layout
- `src/` — packages, logging, REPL, protocol, TCP, run entrypoint
- `tests/` — Rove test suites invoked by ASDF `test-op`
- `scripts/` — helper clients and a stdio↔TCP bridge
- `lisp-mcp-server.asd` — main and test systems (delegates `test-op` to Rove)

## Security Notes
- Reader and runtime evaluation are both enabled. Treat this as a trusted,
  local-development tool; untrusted input can execute arbitrary code in the
  host Lisp image.
- If exposure beyond trusted usage is planned, add allowlists, resource/time
  limits, and output caps.

## Troubleshooting
- Bridge exits after a few seconds of inactivity: ensure you’re using the
  bundled `scripts/stdio_tcp_bridge.py` (it disables read timeouts after
  connect) and that your stdin remains open.
- Permission errors compiling FASLs during tests: allow writes under `~/.cache`
  or reconfigure SBCL’s cache path.
- No output on stdio: remember the protocol is one JSON‑RPC message per line.
  Each request must end with a newline and the server will answer with exactly
  one line (or nothing for notifications).

## Roadmap
- Error taxonomy as condition types mapped to JSON‑RPC errors
- Additional tools (read‑only file access, symbol lookup, etc.)
- CI (GitHub Actions) matrix for SBCL/macOS/Linux

## License
MIT
