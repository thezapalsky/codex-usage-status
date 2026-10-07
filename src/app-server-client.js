import { spawn } from "node:child_process";
import { accessSync, constants } from "node:fs";
import { createInterface } from "node:readline";

const DEFAULT_CODEX_BINS = [
  "/Applications/Codex.app/Contents/Resources/codex",
  "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
  "/Applications/ChatGPT.app/Contents/Resources/codex",
];
const DEFAULT_TIMEOUT_MS = 20_000;

function isExecutable(filePath) {
  try {
    accessSync(filePath, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export function resolveCodexBin(options = {}) {
  const environment = options.env ?? process.env;
  if (environment.CODEX_BIN) {
    return environment.CODEX_BIN;
  }

  const candidates = options.candidates ?? DEFAULT_CODEX_BINS;
  const executableCheck = options.isExecutable ?? isExecutable;
  return candidates.find(executableCheck) ?? candidates[0];
}

export class AppServerClient {
  constructor(options = {}) {
    this.codexBin = options.codexBin ?? resolveCodexBin();
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.nextId = 1;
    this.pending = new Map();
    this.stderrTail = "";
  }

  async start() {
    if (this.child) {
      return;
    }

    this.child = spawn(this.codexBin, ["app-server", "--listen", "stdio://"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
    });

    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk) => {
      this.stderrTail = redactSensitive(`${this.stderrTail}${chunk}`).slice(-4000);
    });

    this.child.on("exit", () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error("Codex app-server exited before responding."));
      }
      this.pending.clear();
    });

    const lines = createInterface({ input: this.child.stdout });
    lines.on("line", (line) => {
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }

      if (message.id === undefined) {
        return;
      }

      const pending = this.pending.get(String(message.id));
      if (!pending) {
        return;
      }

      this.pending.delete(String(message.id));
      clearTimeout(pending.timeout);

      if (message.error) {
        pending.reject(new Error(JSON.stringify(message.error)));
      } else {
        pending.resolve(message.result ?? message);
      }
    });
  }

  async initialize() {
    await this.request("initialize", {
      clientInfo: {
        name: "codex_usage_status",
        title: "Codex Usage Status",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: true,
      },
    });
    this.notify("initialized");
  }

  async readRateLimits() {
    return this.request("account/rateLimits/read");
  }

  async request(method, params) {
    await this.start();

    const id = this.nextId++;
    const payload = params === undefined ? { method, id } : { method, id, params };
    const line = `${JSON.stringify(payload)}\n`;

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(String(id));
        reject(new Error(`Timed out waiting for ${method}. ${this.stderrTail}`.trim()));
      }, this.timeoutMs);

      this.pending.set(String(id), { resolve, reject, timeout });
      this.child.stdin.write(line, (error) => {
        if (error) {
          clearTimeout(timeout);
          this.pending.delete(String(id));
          reject(error);
        }
      });
    });
  }

  notify(method, params) {
    if (!this.child) {
      throw new Error("Codex app-server is not running.");
    }

    const payload = params === undefined ? { method } : { method, params };
    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  async close() {
    if (!this.child) {
      return;
    }

    this.child.stdin.end();
    await new Promise((resolve) => {
      const timeout = setTimeout(() => {
        this.child.kill("SIGTERM");
        resolve();
      }, 1000);
      this.child.once("exit", () => {
        clearTimeout(timeout);
        resolve();
      });
    });
    this.child = undefined;
  }
}

export async function readCodexRateLimits(options = {}) {
  const client = new AppServerClient(options);
  try {
    await client.initialize();
    return await client.readRateLimits();
  } finally {
    await client.close();
  }
}

export function redactSensitive(value) {
  return value
    .replace(/[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/g, "[redacted-jwt]")
    .replace(/((?:token|cookie|session|authorization|api[_-]?key)\s*[:=]\s*)[^\r\n]+/gi, "$1[redacted]");
}
