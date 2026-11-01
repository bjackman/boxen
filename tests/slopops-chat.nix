# The slopops chat server in a VM, with the real claude CLI and Agent SDK. What
# it fakes is the model: an Anthropic API that answers "touch <file>" with that
# Bash command and anything else with text, so that every turn that touches a
# file asks for approval.
{ pkgs }:
let
  socketPath = "/run/slopops-chat.sock";
  homePath = "/var/lib/slopops";
  workPath = "${homePath}/work";
  apiPort = 8090;

  fakeApi = pkgs.writers.writePython3 "fake-anthropic-api" { } ''
    import json
    import re
    import uuid
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


    def answer(request):
        messages = [m for m in request["messages"] if m["role"] == "user"]
        content = messages[-1]["content"]
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        if any(block.get("type") == "tool_result" for block in content):
            return [{"type": "text", "text": "Done."}], "end_turn"
        match = re.search(r"touch ([\w.-]+)", json.dumps(content))
        if match and request.get("tools"):
            return [
                {
                    "type": "tool_use",
                    "id": f"toolu_{uuid.uuid4().hex}",
                    "name": "Bash",
                    "input": {
                        "command": f"touch {match.group(1)}",
                        "description": "Create a file",
                    },
                }
            ], "tool_use"
        return [{"type": "text", "text": "pong"}], "end_turn"


    def stream_events(message):
        content = message["content"]
        yield {"type": "message_start", "message": {**message, "content": []}}
        for index, block in enumerate(content):
            if block["type"] == "text":
                yield {
                    "type": "content_block_start",
                    "index": index,
                    "content_block": {"type": "text", "text": ""},
                }
                delta = {"type": "text_delta", "text": block["text"]}
            else:
                yield {
                    "type": "content_block_start",
                    "index": index,
                    "content_block": {**block, "input": {}},
                }
                delta = {
                    "type": "input_json_delta",
                    "partial_json": json.dumps(block["input"]),
                }
            yield {"type": "content_block_delta", "index": index, "delta": delta}
            yield {"type": "content_block_stop", "index": index}
        yield {
            "type": "message_delta",
            "delta": {
                "stop_reason": message["stop_reason"],
                "stop_sequence": None,
            },
            "usage": {"output_tokens": 1},
        }
        yield {"type": "message_stop"}


    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers["content-length"])
            request = json.loads(self.rfile.read(length))
            if self.path.startswith("/v1/messages/count_tokens"):
                return self.send_json({"input_tokens": 1})
            if not self.path.startswith("/v1/messages"):
                return self.send_json({"type": "error"}, 404)
            content, stop_reason = answer(request)
            message = {
                "id": f"msg_{uuid.uuid4().hex}",
                "type": "message",
                "role": "assistant",
                "model": request["model"],
                "content": content,
                "stop_reason": stop_reason,
                "stop_sequence": None,
                "usage": {"input_tokens": 1, "output_tokens": 1},
            }
            if not request.get("stream"):
                return self.send_json(message)
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            for event in stream_events(message):
                data = json.dumps(event)
                self.wfile.write(
                    f"event: {event['type']}\ndata: {data}\n\n".encode()
                )

        def send_json(self, body, status=200):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


    ThreadingHTTPServer(("127.0.0.1", ${toString apiPort}), Handler).serve_forever()
  '';
in
pkgs.testers.runNixOSTest {
  name = "slopops-chat";
  nodes.machine = {
    imports = [ ../nixos_modules/slopops-chat.nix ];
    virtualisation.memorySize = 2048;

    users.users.slopops = {
      isSystemUser = true;
      group = "slopops";
      home = homePath;
      createHome = true;
    };
    users.groups.slopops = { };
    users.users.proxy = {
      isSystemUser = true;
      group = "proxy";
    };
    users.groups.proxy = { };
    systemd.tmpfiles.rules = [ "d ${workPath} 0755 slopops slopops -" ];

    bjackman.slopopsChat = {
      enable = true;
      user = "slopops";
      allowedUser = "alice";
      inherit socketPath;
      socketGroup = "proxy";
      workingDirPath = workPath;
      stateDirPath = "${homePath}/chat";
      vapidSubject = "https://chat.example";
    };
    systemd.services.slopops-chat = {
      after = [ "fake-anthropic-api.service" ];
      environment = {
        ANTHROPIC_BASE_URL = "http://127.0.0.1:${toString apiPort}";
        ANTHROPIC_API_KEY = "sk-ant-test";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_AUTOUPDATER = "1";
      };
    };

    systemd.services.fake-anthropic-api = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = fakeApi;
    };

    environment.systemPackages = [ pkgs.curl ];
  };

  testScript = ''
    import json
    import shlex
    import time

    def curl(*args, user="alice", as_user="proxy", headers=()):
        header_args = [f"-H 'Remote-User: {user}'"] if user else []
        header_args += [f"-H {shlex.quote(h)}" for h in headers]
        return (
            f"runuser -u {as_user} -- curl -s --unix-socket ${socketPath} "
            + " ".join(header_args + list(args))
        )

    def status(path, *args, **kwargs):
        return machine.succeed(curl("-o /dev/null -w '%{http_code}'", *args, f"http://chat{path}", **kwargs))

    def post(path, body, **kwargs):
        return status(
            path,
            "-X POST",
            f"-d {shlex.quote(json.dumps(body))}",
            headers=["Sec-Fetch-Site: same-origin", "Content-Type: application/json"],
            **kwargs,
        )

    def watch(unit):
        machine.succeed(f"systemd-run --unit={unit} -p Environment=PATH=/run/current-system/sw/bin sh -c {shlex.quote(curl('-N http://chat/api/stream') + f' >/tmp/{unit}.log')}")

    def events(unit):
        out = machine.succeed(f"cat /tmp/{unit}.log 2>/dev/null || true")
        return [json.loads(line[len("data: "):]) for line in out.splitlines() if line.startswith("data: ")]

    def wait_for_event(unit, predicate, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for event in events(unit):
                if predicate(event):
                    return event
            time.sleep(1)
        raise Exception(f"no matching event in {unit}: {events(unit)}")

    machine.wait_for_unit("slopops-chat.socket")
    machine.wait_for_unit("fake-anthropic-api.service")

    with subtest("only the proxy's group can connect to the socket"):
        assert machine.succeed("stat -c '%U %G %a' ${socketPath}").strip() == "root proxy 660"
        assert status("/") == "200"
        machine.fail(curl("http://chat/", as_user="slopops"))

    with subtest("requests must come from the allowed user, and POSTs from the page"):
        assert status("/", user=None) == "403"
        assert status("/", user="mallory") == "403"
        assert status("/api/messages", "-X POST", "-d '{}'") == "403"
        assert status("/api/messages", "-X POST", "-d '{}'", headers=["Sec-Fetch-Site: cross-site"]) == "403"
        assert status("/nope") == "404"

    with subtest("the page and its assets are served"):
        for path in ["/app.js", "/marked.js", "/sw.js", "/style.css", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png", "/icon-maskable-512.png"]:
            assert status(path) == "200", path
        headers = machine.succeed(curl("-D - -o /dev/null http://chat/")).lower()
        assert "content-security-policy: default-src 'self';" in headers, headers
        assert "key" in json.loads(machine.succeed(curl("http://chat/api/push/key")))

    with subtest("the stream sends its headers before there are any events"):
        out = machine.succeed(curl("-i -N --max-time 3 http://chat/api/stream") + " || true")
        assert "text/event-stream" in out, out

    watch("stream")

    with subtest("an approved tool call runs"):
        assert post("/api/messages", {"text": "touch approved"}) == "200"
        approval = wait_for_event("stream", lambda e: e["kind"] == "approval")
        assert approval["tool"] == "Bash", approval
        assert post("/api/approvals", {"id": approval["id"], "allow": True}) == "200"
        wait_for_event("stream", lambda e: e["kind"] == "decision" and e["id"] == approval["id"] and e["allow"])
        wait_for_event("stream", lambda e: e["kind"] == "turnEnd" and e["ok"])
        machine.succeed("test -e ${workPath}/approved")

    with subtest("a denied tool call doesn't"):
        assert post("/api/messages", {"text": "touch denied"}) == "200"
        approval = wait_for_event("stream", lambda e: e["kind"] == "approval" and "denied" in json.dumps(e["input"]))
        assert post("/api/approvals", {"id": approval["id"], "allow": False}) == "200"
        wait_for_event("stream", lambda e: e["kind"] == "decision" and e["id"] == approval["id"] and not e["allow"])
        wait_for_event("stream", lambda e: e["kind"] == "toolResult" and e["isError"])
        machine.fail("test -e ${workPath}/denied")
        assert post("/api/approvals", {"id": approval["id"], "allow": True}) == "409"

    with subtest("a restart cancels a pending approval and resumes the conversation"):
        assert post("/api/messages", {"text": "touch pending"}) == "200"
        approval = wait_for_event("stream", lambda e: e["kind"] == "approval" and "pending" in json.dumps(e["input"]))
        machine.succeed("systemctl restart slopops-chat.service")
        watch("stream-after-restart")
        wait_for_event(
            "stream-after-restart",
            lambda e: e["kind"] == "decision" and e["id"] == approval["id"] and e["reason"] == "cancelled",
        )
        wait_for_event("stream-after-restart", lambda e: e["kind"] == "turnEnd" and not e["ok"])
        machine.fail("test -e ${workPath}/pending")
        session = json.loads(machine.succeed("cat ${homePath}/chat/session.json"))
        assert session.get("sessionId"), session

        assert post("/api/messages", {"text": "touch resumed"}) == "200"
        approval = wait_for_event("stream-after-restart", lambda e: e["kind"] == "approval" and "resumed" in json.dumps(e["input"]))
        assert post("/api/approvals", {"id": approval["id"], "allow": True}) == "200"
        machine.wait_until_succeeds("test -e ${workPath}/resumed", timeout=120)
        assert json.loads(machine.succeed("cat ${homePath}/chat/session.json")) == session

    with subtest("a reset forgets the session"):
        assert post("/api/reset", {}) == "200"
        wait_for_event("stream-after-restart", lambda e: e["kind"] == "reset")
        assert "sessionId" not in json.loads(machine.succeed("cat ${homePath}/chat/session.json"))
  '';
}
