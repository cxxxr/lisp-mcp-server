#!/usr/bin/env python3
"""
Stdio↔TCP line bridge for MCP.

Reads newline-delimited JSON requests from stdin and forwards them to a
TCP MCP server; forwards server responses back to stdout. Logs go to stderr.

Usage:
  python3 scripts/stdio_tcp_bridge.py --host 127.0.0.1 --port 12345

Environment variables (fallbacks):
  LISP_MCP_HOST, LISP_MCP_PORT

Notes:
  - Only forwards single-line messages (newline-delimited JSON).
  - Exits when stdin hits EOF or the TCP connection closes.
  - Keep stdout strictly for protocol lines; logs go to stderr.
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import threading
import time


def eprint(*a, **k):
    print(*a, file=sys.stderr, **k)


def bridge(host: str, port: int, connect_timeout: float = 5.0) -> int:
    try:
        sock = socket.create_connection((host, port), timeout=connect_timeout)
        # Disable read timeouts after connect: MCP connections can idle for long periods.
        # Only the connect phase should be bounded by time.
        try:
            sock.settimeout(None)
        except Exception:
            # If disabling timeouts fails, continue; reads may still work but could be fragile.
            pass
    except Exception as e:
        eprint(f"[bridge] connect failed: {e}")
        return 2

    sock_file_r = sock.makefile('r', encoding='utf-8', newline='')
    sock_file_w = sock.makefile('w', encoding='utf-8', newline='\n')

    stop = threading.Event()

    def pump_stdin_to_tcp():
        try:
            for line in sys.stdin:
                # Pass through as-is; ensure newline
                if not line.endswith('\n'):
                    line += '\n'
                sock_file_w.write(line)
                sock_file_w.flush()
        except Exception as e:
            eprint(f"[bridge] stdin→tcp error: {e}")
        finally:
            try:
                sock_file_w.flush()
            except Exception:
                pass
            try:
                sock.shutdown(socket.SHUT_WR)
            except Exception:
                pass
            stop.set()

    def pump_tcp_to_stdout():
        try:
            for line in sock_file_r:
                sys.stdout.write(line)
                try:
                    sys.stdout.flush()
                except Exception:
                    pass
        except Exception as e:
            eprint(f"[bridge] tcp→stdout error: {e}")
        finally:
            stop.set()

    t1 = threading.Thread(target=pump_stdin_to_tcp, name="stdin→tcp", daemon=True)
    t2 = threading.Thread(target=pump_tcp_to_stdout, name="tcp→stdout", daemon=True)
    t1.start(); t2.start()

    try:
        while not stop.is_set():
            time.sleep(0.05)
    finally:
        try:
            sock_file_r.close()
        except Exception:
            pass
        try:
            sock_file_w.close()
        except Exception:
            pass
        try:
            sock.close()
        except Exception:
            pass
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="MCP stdio↔TCP bridge")
    ap.add_argument("--host", default=os.environ.get("LISP_MCP_HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("LISP_MCP_PORT", "12345")))
    ap.add_argument("--connect-timeout", type=float, default=5.0)
    args = ap.parse_args()
    eprint(f"[bridge] connecting tcp://{args.host}:{args.port}")
    rc = bridge(args.host, args.port, args.connect_timeout)
    eprint(f"[bridge] exit {rc}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
