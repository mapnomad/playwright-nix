#!/usr/bin/env bun
/**
 * Updates Cachix pins for latest browser closures.
 * Builds, pushes, and pins missing/stale outputs.
 *
 * Usage:
 *   bun scripts/push-browsers.ts [--dry-run] <cache-name> [keep-revisions] [tool...]
 *
 * Tools default to: cli dotnet mcp node python
 * Set FORCE=1 to push every selected tool without checking pins.
 * Set CACHIX_API_URL to override the public pin-list endpoint.
 */

import { spawnSync } from "child_process";

function log(msg: string) {
  console.error(`[cachix:latest-browsers] ${msg}`);
}

function die(msg: string): never {
  log(`ERROR: ${msg}`);
  process.exit(1);
}

function usage() {
  console.error(`Usage: bun scripts/push-browsers.ts [--dry-run] <cache-name> [keep-revisions] [tool...]

Tools default to: cli dotnet mcp node python
Set FORCE=1 to push every selected tool without checking pins.
Set CACHIX_API_URL to override the public pin-list endpoint.`);
}

function run(
  cmd: string,
  args: string[],
  opts: { input?: string } = {},
): { status: number; stdout: string; stderr: string } {
  const res = spawnSync(cmd, args, { encoding: "utf8", input: opts.input });
  if (res.error) die(`failed to run ${cmd}: ${res.error.message}`);
  return {
    status: res.status ?? 1,
    stdout: res.stdout ?? "",
    stderr: res.stderr ?? "",
  };
}

const TOOLS = ["cli", "dotnet", "mcp", "node", "python", "camoufox"] as const;
type Tool = (typeof TOOLS)[number];

function resolveTool(tool: string): { pinName: string; attr: string } {
  if (!TOOLS.includes(tool as Tool)) {
    die(`unknown tool '${tool}' (expected ${TOOLS.join("|")})`);
  }
  const name = tool === "camoufox" ? "camoufox" : `playwright-${tool}`;
  return {
    pinName: `${name}-browsers-${SYSTEM}`,
    attr: `.#${name}-browsers`,
  };
}

interface CachixPin {
  name: string;
  lastRevision: { storePath: string };
}

function loadPinState(apiUrl: string): {
  known: boolean;
  reason: string;
  pins: CachixPin[];
} {
  log(`fetching Cachix pins from ${apiUrl}`);
  const res = run("curl", [
    "--silent",
    "--show-error",
    "--location",
    "--fail-with-body",
    apiUrl,
  ]);
  if (res.status !== 0) {
    const reason = `request failed for ${apiUrl}`;
    log(`Cachix pin state is unknown: ${reason}`);
    return { known: false, reason, pins: [] };
  }

  let pins: CachixPin[];
  try {
    pins = JSON.parse(res.stdout);
    if (
      !Array.isArray(pins) ||
      !pins.every(
        (p) =>
          p &&
          typeof p === "object" &&
          typeof p.name === "string" &&
          typeof p.lastRevision === "object" &&
          typeof p.lastRevision?.storePath === "string",
      ) ||
      new Set(pins.map((p) => p.name)).size !== pins.length
    ) {
      throw new Error("malformed shape");
    }
  } catch {
    const reason = `malformed response from ${apiUrl}`;
    log(`Cachix pin state is unknown: ${reason}`);
    return { known: false, reason, pins: [] };
  }

  return { known: true, reason: "", pins };
}

function pushAndPin(
  pinName: string,
  attr: string,
  expectedPath: string,
  cacheName: string,
  keepRevisions: string,
) {
  log(`building ${attr}`);
  const build = run("nix", ["build", "--no-link", "--print-out-paths", attr]);
  if (build.status !== 0) die(`nix build failed for ${attr}: ${build.stderr}`);
  const builtPath = build.stdout.trim();
  if (builtPath !== expectedPath) {
    die(`${attr} evaluated to ${expectedPath} but built as ${builtPath}`);
  }

  log(`pushing runtime closure for ${pinName}`);
  const pathInfo = run("nix", ["path-info", "-r", builtPath]);
  if (pathInfo.status !== 0) {
    die(`nix path-info failed for ${builtPath}: ${pathInfo.stderr}`);
  }
  const push = run("cachix", ["push", cacheName], { input: pathInfo.stdout });
  if (push.status !== 0) die(`cachix push failed: ${push.stderr}`);

  log(`pinning ${pinName} -> ${builtPath}`);
  const pin = run("cachix", [
    "pin",
    cacheName,
    pinName,
    builtPath,
    "--keep-revisions",
    keepRevisions,
  ]);
  if (pin.status !== 0) die(`cachix pin failed: ${pin.stderr}`);
}

function reconcileTool(
  pinName: string,
  attr: string,
  cacheName: string,
  keepRevisions: string,
  dryRun: boolean,
  force: boolean,
  pinState: { known: boolean; reason: string; pins: CachixPin[] },
) {
  log(`evaluating ${attr}.outPath`);
  const evalRes = run("nix", ["eval", "--raw", `${attr}.outPath`]);
  if (evalRes.status !== 0) {
    die(`nix eval failed for ${attr}.outPath: ${evalRes.stderr}`);
  }
  const currentPath = evalRes.stdout.trim();

  if (force) {
    log(`${pinName}: force enabled -> push (${currentPath})`);
  } else if (!pinState.known) {
    log(`${pinName}: cache state unknown (${pinState.reason}) -> push`);
  } else {
    const pinned = pinState.pins.find((p) => p.name === pinName);
    if (!pinned) {
      log(`${pinName}: pin missing -> push (${currentPath})`);
    } else if (pinned.lastRevision.storePath === currentPath) {
      log(`${pinName}: already pinned, skipping (${currentPath})`);
      return;
    } else {
      log(
        `${pinName}: stale (${pinned.lastRevision.storePath} != ${currentPath}) -> push`,
      );
    }
  }

  if (dryRun) {
    log(`${pinName}: dry-run, no build/push/pin performed`);
    return;
  }
  pushAndPin(pinName, attr, currentPath, cacheName, keepRevisions);
}

const SYSTEM = run("nix", [
  "eval",
  "--raw",
  "--impure",
  "--expr",
  "builtins.currentSystem",
]).stdout.trim();

function main() {
  const rawArgs = process.argv.slice(2);
  let dryRun = false;
  const positional: string[] = [];

  for (let i = 0; i < rawArgs.length; i++) {
    const arg = rawArgs[i];
    if (arg === "--dry-run") {
      dryRun = true;
    } else if (arg === "-h" || arg === "--help") {
      usage();
      process.exit(0);
    } else if (arg === "--") {
      positional.push(...rawArgs.slice(i + 1));
      break;
    } else if (arg.startsWith("-")) {
      die(`unknown option '${arg}'`);
    } else {
      positional.push(arg);
    }
  }

  if (positional.length === 0) {
    usage();
    die("cache name required");
  }

  const [cacheName, ...rest] = positional;
  let keepRevisions = "1";
  if (rest.length > 0 && /^\d+$/.test(rest[0])) {
    keepRevisions = rest.shift()!;
  }

  const forceEnv = process.env.FORCE ?? "0";
  if (forceEnv !== "0" && forceEnv !== "1") {
    die(`FORCE must be 0 or 1, got '${forceEnv}'`);
  }
  const force = forceEnv === "1";

  const apiUrl =
    process.env.CACHIX_API_URL ??
    `https://app.cachix.org/api/v1/cache/${cacheName}/pin`;

  const tools =
    rest.length > 0 ? rest : ["cli", "dotnet", "mcp", "node", "python"];

  const pinState = force
    ? { known: false, reason: "comparison bypassed", pins: [] }
    : loadPinState(apiUrl);
  if (force) log("FORCE=1; bypassing Cachix pin comparison");

  for (const tool of tools) {
    const { pinName, attr } = resolveTool(tool);
    reconcileTool(
      pinName,
      attr,
      cacheName,
      keepRevisions,
      dryRun,
      force,
      pinState,
    );
  }
}

main();
