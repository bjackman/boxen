// The slopops agent's deploy tool, as an MCP server. It's a tool of its own,
// rather than a command the agent runs from Bash, so that Claude Code can ask
// before each deploy: see design_docs/slopops.md. What may be deployed is
// enforced by the host, see nixos_modules/slop-deploy.nix.
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// slop-deploy is slop-probe pointed at the hosts' deploy accounts. Like
// slop-probe it comes from the caller's PATH, because it needs keys and hosts
// configured for wherever this runs.
const hosts = await promisify(execFile)("slop-deploy", ["hosts"]).then(
  ({ stdout }) => stdout.split("\n").filter((line) => line !== ""),
  (err) => {
    console.error(`slopops-mcp: running slop-deploy from PATH: ${err.message}`);
    process.exit(1);
  },
);
if (hosts.length === 0) {
  console.error("slopops-mcp: slop-deploy knows no hosts");
  process.exit(1);
}

// The deploy log is mostly build output, and its end is what says how it went.
const maxToolOutput = 20_000;

function runDeploy(host: string, rev: string): Promise<{ status: number; output: string }> {
  return new Promise((resolve) => {
    const child = spawn("slop-deploy", [host, "deploy", `--rev=${rev}`], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", (chunk) => (output += chunk));
    child.stderr.on("data", (chunk) => (output += chunk));
    child.on("error", (err) => resolve({ status: -1, output: `running slop-deploy: ${err.message}` }));
    child.on("close", (status) => resolve({ status: status ?? -1, output }));
  });
}

const server = new McpServer({ name: "slopops", version: "0.1.0" });

server.registerTool(
  "deploy",
  {
    description:
      "Deploy a commit of master to a host, and wait for the deploy to finish. A host only " +
      "accepts the tip of master or a commit of it from the last 30 days. A non-zero exit " +
      "status means the deploy failed, or switched to the new system but left units failed; " +
      "the log says which.",
    inputSchema: {
      host: z.enum(hosts as [string, ...string[]]).describe("Host to deploy"),
      rev: z
        .string()
        .regex(/^[0-9a-f]{40}$/)
        .describe("Full 40-character hash of the commit"),
    },
  },
  async ({ host, rev }) => {
    console.error(`slopops-mcp: deploying ${rev} to ${host}`);
    const { status, output } = await runDeploy(host, rev);
    console.error(`slopops-mcp: deploy of ${rev} to ${host} exited with status ${status}`);
    const tail =
      output.length > maxToolOutput
        ? `[${output.length - maxToolOutput} earlier bytes of the log omitted]\n` +
          output.slice(-maxToolOutput)
        : output;
    return {
      content: [{ type: "text", text: `Exit status ${status}\n\n${tail}` }],
      isError: status !== 0,
    };
  },
);

await server.connect(new StdioServerTransport());
