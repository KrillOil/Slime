"""Run the exported Package 2C benchmark in installed Chrome with a hard watchdog."""

from __future__ import annotations

import argparse
import http.server
import json
import pathlib
import subprocess
import tempfile
import threading
import time


class ResultHandler(http.server.SimpleHTTPRequestHandler):
    result_event: threading.Event
    result_path: pathlib.Path

    def log_message(self, format_string: str, *args: object) -> None:
        print("HTTP " + (format_string % args), flush=True)

    def do_POST(self) -> None:
        if self.path != "/p2c-result":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 20_000_000:
            self.send_error(400, "invalid result length")
            return
        payload = self.rfile.read(length)
        try:
            result = json.loads(payload)
            if result.get("schema") != "package-2c-flow-benchmark-result-v1":
                raise ValueError("unexpected result schema")
            if result.get("platform") != "web":
                raise ValueError("result did not run on the Web platform")
        except (json.JSONDecodeError, ValueError) as error:
            self.send_error(400, str(error))
            return
        self.result_path.write_bytes(payload)
        self.send_response(204)
        self.end_headers()
        self.result_event.set()


def terminate_process_tree(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        process.kill()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--chrome", type=pathlib.Path, required=True)
    parser.add_argument("--web-root", type=pathlib.Path, required=True)
    parser.add_argument("--result", type=pathlib.Path, required=True)
    parser.add_argument("--profile-root", type=pathlib.Path, required=True)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--watchdog-seconds", type=int, default=170)
    args = parser.parse_args()

    if not args.chrome.is_file():
        raise FileNotFoundError(args.chrome)
    if not (args.web_root / "index.html").is_file():
        raise FileNotFoundError(args.web_root / "index.html")
    args.result.parent.mkdir(parents=True, exist_ok=True)
    args.profile_root.mkdir(parents=True, exist_ok=True)

    event = threading.Event()
    handler = lambda *handler_args, **handler_kwargs: ResultHandler(
        *handler_args, directory=str(args.web_root), **handler_kwargs
    )
    ResultHandler.result_event = event
    ResultHandler.result_path = args.result
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    profile = pathlib.Path(
        tempfile.mkdtemp(prefix="chrome-p2c-", dir=args.profile_root)
    )
    chrome_command = [
        str(args.chrome),
        f"--user-data-dir={profile}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-timer-throttling",
        "--disable-renderer-backgrounding",
        "--disable-backgrounding-occluded-windows",
        "--window-size=960,540",
        f"http://127.0.0.1:{args.port}/index.html",
    ]
    print("CHROME_COMMAND " + json.dumps(chrome_command), flush=True)
    print(
        f"WATCHDOG_SECONDS {args.watchdog_seconds} "
        "(covers setup + 10s warmup + 120s measurement + teardown)",
        flush=True,
    )
    process = subprocess.Popen(
        chrome_command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    started = time.monotonic()
    try:
        if not event.wait(args.watchdog_seconds):
            raise TimeoutError(
                f"Chrome benchmark produced no result within "
                f"{args.watchdog_seconds} seconds"
            )
        elapsed = time.monotonic() - started
        result = json.loads(args.result.read_text(encoding="utf-8"))
        print(f"CHROME_RESULT_SECONDS {elapsed:.3f}", flush=True)
        print("P2C_CHROME_RESULT " + json.dumps(result, separators=(",", ":")), flush=True)
        return 0
    finally:
        terminate_process_tree(process)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)
        print("CHROME_TEARDOWN_COMPLETE", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
