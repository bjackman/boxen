// What the chat server streams to the page. The log of these is the
// conversation as the page shows it; the agent's own transcript is the SDK's.
export type ChatEventBody =
  | { kind: "user"; text: string }
  | { kind: "text"; text: string }
  | { kind: "tool"; id: string; name: string; input: unknown }
  | { kind: "toolResult"; id: string; text: string; isError: boolean }
  | { kind: "approval"; id: string; tool: string; title: string; input: unknown }
  | { kind: "decision"; id: string; allow: boolean; reason: "user" | "cancelled" }
  | { kind: "turnEnd"; ok: boolean; error?: string }
  | { kind: "reset" }
  | { kind: "restarted" }
  | { kind: "masterMoved"; from: string; to: string };

export type ChatEvent = ChatEventBody & { seq: number; at: string };
