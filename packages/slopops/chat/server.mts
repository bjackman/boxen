// slopops behind a chat page: the agent runs here through the Agent SDK, and
// the page reaches this server through Caddy and Authelia.
//
// Approving a tool call is a POST to this server, so who can connect to it
// decides who can approve a deploy. Only the reverse proxy should be able to
// connect, and it still checks the user Authelia vouched for.
import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { extname, join } from "node:path";
import {
  query,
  type CanUseTool,
  type McpServerConfig,
  type PermissionResult,
  type Query,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import webpush from "web-push";
import type { ChatEvent, ChatEventBody } from "./events.ts";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`slopops-chat: ${name} is not set`);
    process.exit(1);
  }
  return value;
}

const stateDirPath = requireEnv("SLOPOPS_CHAT_STATE_DIR");
const webDirPath = requireEnv("SLOPOPS_CHAT_WEB_DIR");
const claudePath = requireEnv("SLOPOPS_CHAT_CLAUDE_PATH");
const mcpConfigPath = requireEnv("SLOPOPS_CHAT_MCP_CONFIG");
const allowedUser = requireEnv("SLOPOPS_CHAT_USER");
const vapidSubject = requireEnv("SLOPOPS_CHAT_VAPID_SUBJECT");

await mkdir(stateDirPath, { recursive: true });

async function readJson<T>(path: string, fallback: () => T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return fallback();
    throw new Error(`reading ${path}: ${(err as Error).message}`);
  }
}

const writes = new Map<string, Promise<void>>();

// Each file's writes run one at a time, since they share the temporary file.
function writeJson(path: string, value: unknown): Promise<void> {
  const tmpPath = `${path}.tmp`;
  const write = (writes.get(path) ?? Promise.resolve())
    .catch(() => {})
    .then(async () => {
      await writeFile(tmpPath, JSON.stringify(value), { mode: 0o600 });
      await rename(tmpPath, path);
    });
  writes.set(path, write);
  return write;
}

const mcpServers = JSON.parse(readFileSync(mcpConfigPath, "utf8")) as Record<string, McpServerConfig>;

// The event log

const eventsPath = join(stateDirPath, "events.jsonl");
const events: ChatEvent[] = await readFile(eventsPath, "utf8").then(
  (text) => text.split("\n").filter((line) => line !== "").map((line) => JSON.parse(line) as ChatEvent),
  (err: NodeJS.ErrnoException) => {
    if (err.code === "ENOENT") return [];
    throw new Error(`reading ${eventsPath}: ${err.message}`);
  },
);
const listeners = new Set<(event: ChatEvent) => void>();
let turnOpen = false;

function record(event: ChatEvent): void {
  if (event.kind === "user") turnOpen = true;
  if (event.kind === "turnEnd" || event.kind === "reset") turnOpen = false;
}
events.forEach(record);

function emit(body: ChatEventBody): void {
  const event = { ...body, seq: events.length + 1, at: new Date().toISOString() } as ChatEvent;
  events.push(event);
  record(event);
  appendFileSync(eventsPath, JSON.stringify(event) + "\n", { mode: 0o600 });
  for (const listener of listeners) listener(event);
}

// Approvals asked for before a restart can't be answered any more.
{
  const decided = new Set(events.flatMap((e) => (e.kind === "decision" ? [e.id] : [])));
  for (const e of events) {
    if (e.kind === "approval" && !decided.has(e.id)) {
      emit({ kind: "decision", id: e.id, allow: false, reason: "cancelled" });
    }
  }
  if (turnOpen) emit({ kind: "turnEnd", ok: false, error: "slopops-chat restarted during this turn." });
}

// Push notifications

type Vapid = { publicKey: string; privateKey: string };
const vapidPath = join(stateDirPath, "vapid.json");
const vapid = await readJson<Vapid | null>(vapidPath, () => null).then(async (existing) => {
  if (existing) return existing;
  const keys = webpush.generateVAPIDKeys();
  await writeJson(vapidPath, keys);
  return keys;
});
webpush.setVapidDetails(vapidSubject, vapid.publicKey, vapid.privateKey);

const subscriptionsPath = join(stateDirPath, "push-subscriptions.json");
let subscriptions = await readJson<webpush.PushSubscription[]>(subscriptionsPath, () => []);

async function addSubscription(subscription: webpush.PushSubscription): Promise<void> {
  subscriptions = [...subscriptions.filter((s) => s.endpoint !== subscription.endpoint), subscription];
  await writeJson(subscriptionsPath, subscriptions);
}

function notify(title: string, body: string, tag: string): void {
  const payload = JSON.stringify({ title, body, tag });
  for (const subscription of subscriptions) {
    webpush.sendNotification(subscription, payload).catch(async (err: unknown) => {
      if (err instanceof webpush.WebPushError && (err.statusCode === 404 || err.statusCode === 410)) {
        subscriptions = subscriptions.filter((s) => s.endpoint !== subscription.endpoint);
        await writeJson(subscriptionsPath, subscriptions).catch((writeErr: unknown) =>
          console.error(`slopops-chat: dropping an expired push subscription: ${writeErr}`),
        );
        return;
      }
      console.error(`slopops-chat: sending a notification to ${new URL(subscription.endpoint).host}: ${err}`);
    });
  }
}

function truncate(text: string, length: number): string {
  return text.length > length ? `${text.slice(0, length)}…` : text;
}

// The agent

type SessionState = { sessionId?: string };
const sessionPath = join(stateDirPath, "session.json");
const session = await readJson<SessionState>(sessionPath, () => ({}));

// The prompt stream of a query: it stays open between turns, so one CLI
// process serves the whole conversation and canUseTool keeps working.
class Inbox implements AsyncIterable<SDKUserMessage> {
  #queue: SDKUserMessage[] = [];
  #wake: (() => void) | null = null;
  #closed = false;

  push(text: string): void {
    this.#queue.push({ type: "user", message: { role: "user", content: text }, parent_tool_use_id: null });
    this.#wake?.();
  }

  close(): void {
    this.#closed = true;
    this.#wake?.();
  }

  async *[Symbol.asyncIterator](): AsyncIterator<SDKUserMessage> {
    for (;;) {
      const next = this.#queue.shift();
      if (next) {
        yield next;
        continue;
      }
      if (this.#closed) return;
      await new Promise<void>((resolve) => (this.#wake = resolve));
      this.#wake = null;
    }
  }
}

const pendingApprovals = new Map<string, (allow: boolean, reason: "user" | "cancelled") => void>();

function cancelPendingApprovals(): void {
  for (const settle of [...pendingApprovals.values()]) settle(false, "cancelled");
}

const canUseTool: CanUseTool = (toolName, input, { signal, title }) =>
  new Promise<PermissionResult>((resolve) => {
    const id = randomUUID();
    const settle = (allow: boolean, reason: "user" | "cancelled") => {
      if (!pendingApprovals.delete(id)) return;
      emit({ kind: "decision", id, allow, reason });
      resolve(
        allow
          ? { behavior: "allow", updatedInput: input }
          : {
              behavior: "deny",
              message: reason === "user" ? `${allowedUser} denied this.` : "The request was cancelled.",
            },
      );
    };
    pendingApprovals.set(id, settle);
    if (signal.aborted) return settle(false, "cancelled");
    signal.addEventListener("abort", () => settle(false, "cancelled"), { once: true });
    const prompt = title ?? `slopops wants to use ${toolName}`;
    emit({ kind: "approval", id, tool: toolName, title: prompt, input });
    notify("Approval needed", prompt, `approval-${id}`);
  });

let agent: { query: Query; inbox: Inbox } | null = null;

function startAgent(): { query: Query; inbox: Inbox } {
  const inbox = new Inbox();
  const q = query({
    prompt: inbox,
    options: {
      pathToClaudeCodeExecutable: claudePath,
      cwd: process.cwd(),
      resume: session.sessionId,
      permissionMode: "default",
      settingSources: ["user", "project"],
      mcpServers,
      strictMcpConfig: true,
      canUseTool,
      stderr: (data) => process.stderr.write(data),
    },
  });
  const started = { query: q, inbox };
  void runAgent(started);
  return started;
}

async function runAgent(started: { query: Query; inbox: Inbox }): Promise<void> {
  let error = "The agent stopped.";
  try {
    for await (const message of started.query) {
      // After a reset, the old query's last messages belong to the old session.
      if (agent === started) await handleMessage(message);
    }
  } catch (err) {
    console.error(`slopops-chat: running the agent: ${(err as Error).stack}`);
    error = `The agent stopped: ${(err as Error).message}`;
  }
  // Ended without being reset: the next message starts it again, resuming the
  // same session.
  if (agent === started) {
    agent = null;
    cancelPendingApprovals();
    if (turnOpen) emit({ kind: "turnEnd", ok: false, error });
  }
}

function toolResultText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((block: { type?: string; text?: string }) => (block.type === "text" ? block.text : `[${block.type}]`))
    .join("\n");
}

// The page shows the start and end of a tool's output; the agent sees all of it.
const maxToolResultLength = 4000;

async function handleMessage(message: SDKMessage): Promise<void> {
  switch (message.type) {
    case "system":
      if (message.subtype === "init" && session.sessionId !== message.session_id) {
        session.sessionId = message.session_id;
        await writeJson(sessionPath, session);
      }
      break;
    case "assistant":
      for (const block of message.message.content) {
        if (block.type === "text" && block.text.trim() !== "") {
          emit({ kind: "text", text: block.text });
        } else if (block.type === "tool_use") {
          emit({ kind: "tool", id: block.id, name: block.name, input: block.input });
        }
      }
      break;
    case "user":
      if (!Array.isArray(message.message.content)) break;
      for (const block of message.message.content) {
        if (block.type !== "tool_result") continue;
        const text = toolResultText(block.content);
        emit({
          kind: "toolResult",
          id: block.tool_use_id,
          text:
            text.length > maxToolResultLength
              ? `${text.slice(0, maxToolResultLength / 2)}\n[…]\n${text.slice(-maxToolResultLength / 2)}`
              : text,
          isError: block.is_error === true,
        });
      }
      break;
    case "result": {
      const ok = message.subtype === "success" && !message.is_error;
      const error =
        message.subtype === "success" ? (message.is_error ? message.result : undefined) : message.errors.join("\n");
      emit({ kind: "turnEnd", ok, error });
      notify(
        "slopops",
        message.subtype === "success" ? truncate(message.result, 200) : "The turn failed.",
        "turn-end",
      );
      break;
    }
  }
}

function sendMessage(text: string): void {
  agent ??= startAgent();
  emit({ kind: "user", text });
  agent.inbox.push(text);
}

async function resetConversation(): Promise<void> {
  const old = agent;
  agent = null;
  cancelPendingApprovals();
  old?.inbox.close();
  old?.query.close();
  delete session.sessionId;
  await writeJson(sessionPath, session);
  emit({ kind: "reset" });
}

// HTTP

const staticFiles: Record<string, string> = {
  "/": "index.html",
  "/app.js": "app.js",
  "/sw.js": "sw.js",
  "/style.css": "style.css",
  "/manifest.webmanifest": "manifest.webmanifest",
  "/icon.svg": "icon.svg",
};
const contentTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".webmanifest": "application/manifest+json",
  ".svg": "image/svg+xml",
};

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function readBody(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of req as AsyncIterable<Buffer>) {
    length += chunk.length;
    if (length > 1_000_000) throw new HttpError(413, "Request too large");
    chunks.push(chunk);
  }
  try {
    const body: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (typeof body !== "object" || body === null) throw new Error("not an object");
    return body as Record<string, unknown>;
  } catch (err) {
    throw new HttpError(400, `Bad JSON: ${(err as Error).message}`);
  }
}

function sendJson(res: ServerResponse, value: unknown): void {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify(value));
}

function streamEvents(req: IncomingMessage, res: ServerResponse): void {
  const after = Number(req.headers["last-event-id"] ?? 0) || 0;
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-store" });
  res.flushHeaders();
  const write = (event: ChatEvent) => res.write(`id: ${event.seq}\ndata: ${JSON.stringify(event)}\n\n`);
  for (const event of events.slice(after)) write(event);
  listeners.add(write);
  const keepalive = setInterval(() => res.write(": keepalive\n\n"), 30_000);
  req.on("close", () => {
    clearInterval(keepalive);
    listeners.delete(write);
  });
}

async function serveStatic(pathname: string, res: ServerResponse): Promise<void> {
  const name = staticFiles[pathname];
  if (!name) throw new HttpError(404, "Not found");
  res.writeHead(200, { "content-type": contentTypes[extname(name)] ?? "application/octet-stream" });
  res.end(await readFile(join(webDirPath, name)));
}

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  if (req.headers["remote-user"] !== allowedUser) throw new HttpError(403, "Forbidden");
  const { pathname } = new URL(req.url ?? "/", "http://localhost");

  if (req.method === "GET") {
    if (pathname === "/api/stream") return streamEvents(req, res);
    if (pathname === "/api/push/key") return sendJson(res, { key: vapid.publicKey });
    return serveStatic(pathname, res);
  }
  if (req.method !== "POST") throw new HttpError(405, "Method not allowed");
  // Authelia's cookie goes with requests from any site, so refuse those that
  // didn't come from the page.
  if (req.headers["sec-fetch-site"] !== "same-origin") throw new HttpError(403, "Cross-site request");

  const body = await readBody(req);
  switch (pathname) {
    case "/api/messages": {
      if (typeof body.text !== "string" || body.text.trim() === "") throw new HttpError(400, "No text");
      sendMessage(body.text);
      break;
    }
    case "/api/approvals": {
      const settle = typeof body.id === "string" ? pendingApprovals.get(body.id) : undefined;
      if (!settle) throw new HttpError(409, "No such approval is pending");
      settle(body.allow === true, "user");
      break;
    }
    case "/api/interrupt":
      await agent?.query.interrupt();
      break;
    case "/api/reset":
      await resetConversation();
      break;
    case "/api/push/subscriptions": {
      const subscription = body as unknown as webpush.PushSubscription;
      if (typeof subscription.endpoint !== "string" || !URL.canParse(subscription.endpoint)) {
        throw new HttpError(400, "Bad subscription");
      }
      await addSubscription(subscription);
      break;
    }
    default:
      throw new HttpError(404, "Not found");
  }
  sendJson(res, { ok: true });
}

const server = createServer((req, res) => {
  handleRequest(req, res).catch((err: unknown) => {
    const status = err instanceof HttpError ? err.status : 500;
    if (status === 500) console.error(`slopops-chat: handling ${req.method} ${req.url}: ${(err as Error).stack}`);
    if (res.headersSent) return res.end();
    res.writeHead(status, { "content-type": "text/plain; charset=utf-8" });
    res.end((err as Error).message);
  });
});

// From systemd on pizza; SLOPOPS_CHAT_LISTEN=host:port elsewhere.
const listen = process.env.SLOPOPS_CHAT_LISTEN;
if (process.env.LISTEN_FDS === "1") {
  server.listen({ fd: 3 });
} else if (listen) {
  const [host, port] = [listen.slice(0, listen.lastIndexOf(":")), Number(listen.slice(listen.lastIndexOf(":") + 1))];
  server.listen(port, host);
} else {
  console.error("slopops-chat: neither LISTEN_FDS nor SLOPOPS_CHAT_LISTEN is set");
  process.exit(1);
}
console.error("slopops-chat: listening");
