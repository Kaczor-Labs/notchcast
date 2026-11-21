#!/usr/bin/env python3
"""Loopback OpenAI-compatible fixture for the Debug dictation-cleanup scene."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Event


MODELS = ("answer", "fail", "hang", "empty", "long")
RAW = "um so the meeting is at three no wait four pm"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/v1/models":
            self.send_error(404)
            return
        data = json.dumps({"data": [{"id": model} for model in MODELS]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        model = request.get("model")
        messages = request.get("messages", [])
        if not (
            model in MODELS
            and set(request) == {"model", "messages", "stream"}
            and request["stream"] is True
            and len(messages) == 2
            and set(messages[0]) == {"role", "content"}
            and messages[0]["role"] == "system"
            and messages[0]["content"].startswith("You clean up dictated text.")
            and messages[1] == {"role": "user", "content": f"Transcript:\n{RAW}"}
        ):
            self.send_error(400, "Expected only cleanup instructions and the fixture transcript")
            return
        print(json.dumps(request, ensure_ascii=False), flush=True)
        if model == "fail":
            self.send_error(503, "Fixture failure")
            return
        if model == "hang":
            Event().wait(timeout=15)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        if model != "empty":
            answer = "The meeting is at 4 PM." if model == "answer" else "Additional commentary. " * 8
            delta = {"choices": [{"delta": {"content": answer}}]}
            self.wfile.write(f"data: {json.dumps(delta)}\n\n".encode())
        self.wfile.write(b"data: [DONE]\n\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
        print(f"http://127.0.0.1:{server.server_port}/v1", flush=True)
        server.serve_forever()
