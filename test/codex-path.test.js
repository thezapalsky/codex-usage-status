import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { resolveCodexBin } from "../src/app-server-client.js";

const codexDesktop = "/Applications/Codex.app/Contents/Resources/codex";
const chatGPTCurrent = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex";
const chatGPTLegacy = "/Applications/ChatGPT.app/Contents/Resources/codex";

test("explicit CODEX_BIN takes precedence even when the file is missing", () => {
  assert.equal(
    resolveCodexBin({
      env: { CODEX_BIN: "/custom/codex" },
      isExecutable: () => {
        assert.fail("an explicit override must not trigger discovery");
      },
    }),
    "/custom/codex",
  );
});

test("keeps Codex desktop as the first choice when both apps are installed", () => {
  assert.equal(
    resolveCodexBin({ env: {}, isExecutable: () => true }),
    codexDesktop,
  );
});

test("prefers ChatGPT's current bundle path over its legacy path", () => {
  const available = new Set([chatGPTCurrent, chatGPTLegacy]);
  assert.equal(
    resolveCodexBin({ env: {}, isExecutable: (path) => available.has(path) }),
    chatGPTCurrent,
  );
});

test("supports the legacy ChatGPT bundle path", () => {
  assert.equal(
    resolveCodexBin({ env: {}, isExecutable: (path) => path === chatGPTLegacy }),
    chatGPTLegacy,
  );
});

test("keeps the original missing-binary path when no candidate is installed", () => {
  assert.equal(
    resolveCodexBin({ env: {}, isExecutable: () => false }),
    codexDesktop,
  );
});

test("skips missing and non-executable candidates on disk", (t) => {
  const directory = mkdtempSync(join(tmpdir(), "codex-path-test-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));

  const missing = join(directory, "missing");
  const notExecutable = join(directory, "not-executable");
  const executable = join(directory, "codex");
  writeFileSync(notExecutable, "test fixture");
  writeFileSync(executable, "test fixture");
  chmodSync(notExecutable, 0o600);
  chmodSync(executable, 0o700);

  assert.equal(
    resolveCodexBin({ env: {}, candidates: [missing, notExecutable, executable] }),
    executable,
  );
});
