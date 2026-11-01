import type { ChatEvent } from "../events.ts";

function byId<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`no #${id}`);
  return element as T;
}

const log = byId<HTMLElement>("log");
const connection = byId<HTMLElement>("connection");
const composer = byId<HTMLFormElement>("composer");
const message = byId<HTMLTextAreaElement>("message");
const busy = byId<HTMLProgressElement>("busy");
const interrupt = byId<HTMLButtonElement>("interrupt");
const notifications = byId<HTMLButtonElement>("notifications");
const resetDialog = byId<HTMLDialogElement>("reset-dialog");
const approvalTemplate = byId<HTMLTemplateElement>("approval-template");

async function post(path: string, body: unknown = {}): Promise<void> {
  let response: Response;
  try {
    response = await fetch(path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    // Most likely Authelia redirecting a request whose session has expired.
    throw new Error("The request failed. Reload the page to log in again.");
  }
  if (!response.ok) throw new Error(`${response.status}: ${await response.text()}`);
}

function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  el.className = className;
  if (text !== undefined) el.textContent = text;
  return el;
}

function showLocalError(err: unknown): void {
  append(element("p", "error", (err as Error).message));
}

function formatInput(input: unknown): string {
  return JSON.stringify(input, null, 2);
}

function summarizeInput(input: unknown): string {
  if (typeof input !== "object" || input === null) return "";
  const record = input as Record<string, unknown>;
  const value = record.command ?? record.file_path ?? record.pattern ?? record.host;
  return typeof value === "string" ? value : "";
}

function setBusy(value: boolean): void {
  busy.hidden = !value;
  interrupt.hidden = !value;
}

// Follow the conversation as it grows, unless the reader has scrolled up.
function append(el: HTMLElement, parent: HTMLElement = log): void {
  const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 48;
  parent.append(el);
  if (atBottom) log.scrollTop = log.scrollHeight;
}

function render(event: ChatEvent): void {
  switch (event.kind) {
    case "user":
      append(element("p", "user", event.text));
      setBusy(true);
      break;
    case "text":
      append(element("p", "agent", event.text));
      break;
    case "tool": {
      const details = element("details", "tool");
      details.id = `tool-${event.id}`;
      const summary = element("summary", "");
      summary.append(element("code", "", event.name), ` ${summarizeInput(event.input)}`);
      details.append(summary, element("pre", "input", formatInput(event.input)));
      append(details);
      break;
    }
    case "toolResult": {
      const details = document.getElementById(`tool-${event.id}`);
      if (!details) break;
      append(element("pre", "result", event.text || "(no output)"), details);
      details.classList.toggle("failed", event.isError);
      break;
    }
    case "approval": {
      const article = approvalTemplate.content.firstElementChild!.cloneNode(true) as HTMLElement;
      article.id = `approval-${event.id}`;
      article.querySelector(".title")!.textContent = event.title;
      article.querySelector(".input")!.textContent = formatInput(event.input);
      for (const button of article.querySelectorAll("button")) {
        button.addEventListener("click", () => {
          for (const b of article.querySelectorAll("button")) b.disabled = true;
          post("/api/approvals", { id: event.id, allow: button.value === "allow" }).catch((err) => {
            for (const b of article.querySelectorAll("button")) b.disabled = false;
            showLocalError(err);
          });
        });
      }
      append(article);
      break;
    }
    case "decision": {
      const article = document.getElementById(`approval-${event.id}`);
      if (!article) break;
      article.querySelector(".actions")?.remove();
      const outcome = article.querySelector<HTMLElement>(".outcome")!;
      outcome.textContent = event.reason === "cancelled" ? "Cancelled" : event.allow ? "Approved" : "Denied";
      outcome.hidden = false;
      break;
    }
    case "turnEnd":
      setBusy(false);
      if (event.error) append(element("p", "error", event.error));
      break;
    case "reset":
      setBusy(false);
      append(element("p", "reset", "New conversation"));
      break;
  }
}

const stream = new EventSource("/api/stream");
stream.addEventListener("open", () => (connection.textContent = "Connected"));
stream.addEventListener("error", () => (connection.textContent = "Reconnecting…"));
stream.addEventListener("message", (e) => render(JSON.parse(e.data) as ChatEvent));

message.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" || event.shiftKey) return;
  event.preventDefault();
  if (event.isComposing) return;
  composer.requestSubmit();
});

composer.addEventListener("submit", (event) => {
  event.preventDefault();
  const text = message.value;
  if (text.trim() === "") return;
  message.value = "";
  post("/api/messages", { text }).catch((err) => {
    message.value = text;
    showLocalError(err);
  });
});

interrupt.addEventListener("click", () => post("/api/interrupt").catch(showLocalError));

resetDialog.addEventListener("close", () => {
  const reset = resetDialog.returnValue === "reset";
  // A light dismiss leaves the last returnValue in place.
  resetDialog.returnValue = "";
  if (reset) post("/api/reset").catch(showLocalError);
});

// Notifications

async function subscribe(registration: ServiceWorkerRegistration): Promise<void> {
  const response = await fetch("/api/push/key");
  const { key } = (await response.json()) as { key: string };
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: key,
  });
  await post("/api/push/subscriptions", subscription.toJSON());
}

const registration = await navigator.serviceWorker.register("/sw.js");
const existing = await registration.pushManager.getSubscription();
if (existing && Notification.permission === "granted") {
  // The server forgets subscriptions that stop working, so remind it.
  post("/api/push/subscriptions", existing.toJSON()).catch(showLocalError);
} else if (Notification.permission !== "denied") {
  notifications.hidden = false;
}

notifications.addEventListener("click", async () => {
  try {
    if ((await Notification.requestPermission()) !== "granted") return;
    await subscribe(registration);
    notifications.hidden = true;
  } catch (err) {
    showLocalError(err);
  }
});
