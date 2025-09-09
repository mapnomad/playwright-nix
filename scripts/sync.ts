#!/usr/bin/env bun
/**
 * Syncs tools and browsers in packages.lock.
 *
 * Usage:
 *   bun scripts/sync.ts                  # All tools to latest
 *   bun scripts/sync.ts <tool> [version] # Specific tool/version
 *   bun scripts/sync.ts --backfill <tool># Backfill releases
 */

import { spawnSync } from "child_process";
import * as fs from "fs";
import * as path from "path";

function findLockfilePath(): string {
  if (process.env.PLAYWRIGHT_LOCKFILE) {
    return path.resolve(process.env.PLAYWRIGHT_LOCKFILE);
  }
  let dir = process.cwd();
  while (dir !== path.dirname(dir)) {
    const candidate = path.join(dir, "packages.lock");
    if (fs.existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  return path.resolve(__dirname, "../packages.lock");
}

const LOCKFILE_PATH = findLockfilePath();

interface Lockfile {
  version: number;
  tools: Record<
    string,
    {
      latest: string;
      versions: Record<string, any>;
    }
  >;
  coreSets: Record<string, Record<string, string>>;
  browsers: Record<
    string,
    Record<
      string,
      {
        browserVersion?: string;
        hashes: Record<string, string>;
      }
    >
  >;
}

function log(msg: string) {
  console.error(`[sync] ${msg}`);
}

function die(msg: string): never {
  console.error(`[sync] ERROR: ${msg}`);
  process.exit(1);
}

function loadLockfile(): Lockfile {
  if (!fs.existsSync(LOCKFILE_PATH)) {
    die(`Lockfile not found at ${LOCKFILE_PATH}`);
  }
  return JSON.parse(fs.readFileSync(LOCKFILE_PATH, "utf8"));
}

function saveLockfile(lock: Lockfile) {
  fs.writeFileSync(LOCKFILE_PATH, JSON.stringify(lock, null, 2) + "\n");
  log("packages.lock saved.");
}

async function fetchJSON(
  url: string,
  headers: Record<string, string> = {},
): Promise<any> {
  const res = await fetch(url, {
    headers: {
      "User-Agent": "playwright-nix",
      ...headers,
    },
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${url}: ${await res.text()}`);
  }
  return res.json();
}

function prefetchFile(url: string, unpack: boolean = false): string {
  log(`prefetching file: ${url} (unpack=${unpack})`);
  const args = ["store", "prefetch-file", "--json", "--hash-type", "sha256"];
  if (unpack) args.push("--unpack");
  args.push(url);
  const res = spawnSync("nix", args, { encoding: "utf8" });
  if (res.status !== 0) {
    die(`nix store prefetch-file failed for ${url}: ${res.stderr}`);
  }
  return JSON.parse(res.stdout).hash;
}

function prefetchFetchzip(url: string, stripRoot: boolean = true): string {
  log(`prefetching archive: ${url} (stripRoot=${stripRoot})`);
  if (stripRoot) {
    const res = spawnSync("nix-prefetch-url", ["--unpack", url], {
      encoding: "utf8",
    });
    if (res.status !== 0 || !res.stdout) {
      die(`nix-prefetch-url --unpack failed for ${url}: ${res.stderr}`);
    }
    const b32 = res.stdout.trim().split("\n").pop()!.trim();
    const conv = spawnSync(
      "nix",
      ["hash", "convert", "--to", "sri", "--hash-algo", "sha256", b32],
      {
        encoding: "utf8",
      },
    );
    if (conv.status !== 0 || !conv.stdout) {
      die(`nix hash convert failed for ${b32}: ${conv.stderr}`);
    }
    return conv.stdout.trim();
  } else {
    const tmpDir = fs.mkdtempSync(path.join("/tmp", "pw-fetchzip-"));
    try {
      const archive = path.join(tmpDir, "archive.zip");
      const extract = path.join(tmpDir, "extract");
      fs.mkdirSync(extract);
      const curlRes = spawnSync("curl", ["-fsSL", url, "-o", archive]);
      if (curlRes.status !== 0) die(`Failed to download ${url}`);
      const unzipRes = spawnSync("unzip", ["-q", archive, "-d", extract]);
      if (unzipRes.status !== 0) die(`Failed to unzip ${archive}`);
      const hashRes = spawnSync(
        "nix",
        ["hash", "path", "--type", "sha256", "--sri", extract],
        {
          encoding: "utf8",
        },
      );
      if (hashRes.status !== 0 || !hashRes.stdout) {
        die(`nix hash path failed for ${extract}: ${hashRes.stderr}`);
      }
      return hashRes.stdout.trim();
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }
}

function prefetchNpmDepsFromGithub(
  owner: string,
  repo: string,
  rev: string,
): string {
  log(`prefetching npm deps for ${owner}/${repo}@${rev}`);
  const lockUrl = `https://raw.githubusercontent.com/${owner}/${repo}/${rev}/package-lock.json`;
  const tmpDir = fs.mkdtempSync(path.join("/tmp", "pw-npm-deps-"));
  try {
    const lockPath = path.join(tmpDir, "package-lock.json");
    const curlRes = spawnSync("curl", ["-fsSL", lockUrl, "-o", lockPath]);
    if (curlRes.status !== 0) die(`Failed to download ${lockUrl}`);

    const prefetchRes = spawnSync("prefetch-npm-deps", [lockPath], {
      encoding: "utf8",
    });
    if (prefetchRes.status !== 0) {
      die(`prefetch-npm-deps failed: ${prefetchRes.stderr}`);
    }
    return prefetchRes.stdout.trim();
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

const SUPPORTED_SYSTEMS = [
  "x86_64-linux",
  "aarch64-linux",
  "aarch64-darwin",
] as const;
type System = (typeof SUPPORTED_SYSTEMS)[number];

function getBrowserUrl(
  browser: string,
  rev: string,
  browserVersion: string | undefined,
  sys: System,
): { url: string; stripRoot: boolean } {
  if (browser === "chromium") {
    if (sys === "x86_64-linux") {
      return {
        url: `https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-linux64.zip`,
        stripRoot: true,
      };
    } else if (sys === "aarch64-linux") {
      return {
        url: `https://cdn.playwright.dev/builds/chromium/${rev}/chromium-linux-arm64.zip`,
        stripRoot: true,
      };
    } else {
      return {
        url: `https://cdn.playwright.dev/builds/cft/${browserVersion}/mac-arm64/chrome-mac-arm64.zip`,
        stripRoot: false,
      };
    }
  }

  if (browser === "chromium-headless-shell") {
    if (sys === "x86_64-linux") {
      return {
        url: `https://cdn.playwright.dev/builds/cft/${browserVersion}/linux64/chrome-headless-shell-linux64.zip`,
        stripRoot: false,
      };
    } else if (sys === "aarch64-linux") {
      return {
        url: `https://cdn.playwright.dev/builds/chromium/${rev}/chromium-headless-shell-linux-arm64.zip`,
        stripRoot: false,
      };
    } else {
      return {
        url: `https://cdn.playwright.dev/builds/cft/${browserVersion}/mac-arm64/chrome-headless-shell-mac-arm64.zip`,
        stripRoot: false,
      };
    }
  }

  if (browser === "firefox") {
    const archSuffix = {
      "x86_64-linux": "ubuntu-22.04",
      "aarch64-linux": "ubuntu-22.04-arm64",
      "aarch64-darwin": "mac-arm64",
    }[sys];
    return {
      url: `https://cdn.playwright.dev/builds/firefox/${rev}/firefox-${archSuffix}.zip`,
      stripRoot: sys !== "aarch64-darwin",
    };
  }

  if (browser === "webkit") {
    const archSuffix = {
      "x86_64-linux": "ubuntu-22.04",
      "aarch64-linux": "ubuntu-22.04-arm64",
      "aarch64-darwin": "mac-15-arm64",
    }[sys];
    return {
      url: `https://cdn.playwright.dev/builds/webkit/${rev}/webkit-${archSuffix}.zip`,
      stripRoot: sys !== "aarch64-darwin",
    };
  }

  if (browser === "ffmpeg") {
    const archSuffix = {
      "x86_64-linux": "linux",
      "aarch64-linux": "linux-arm64",
      "aarch64-darwin": "mac-arm64",
    }[sys];
    return {
      url: `https://cdn.playwright.dev/builds/ffmpeg/${rev}/ffmpeg-${archSuffix}.zip`,
      stripRoot: false,
    };
  }

  throw new Error(`Unsupported browser: ${browser}`);
}

function resolveGitSha(
  repoUrl: string,
  version: string,
  fallbackGitHead?: string | null,
): string {
  if (
    fallbackGitHead &&
    typeof fallbackGitHead === "string" &&
    fallbackGitHead.length > 0
  ) {
    return fallbackGitHead;
  }
  log(`resolving git SHA for ${repoUrl} tag v${version} or ${version}...`);
  const res = spawnSync("git", ["ls-remote", "--tags", repoUrl], {
    encoding: "utf8",
  });
  if (res.status === 0 && res.stdout) {
    const lines = res.stdout.split("\n");
    for (const tag of [`refs/tags/v${version}`, `refs/tags/${version}`]) {
      const derefMatch = lines.find((l) => l.endsWith(`\t${tag}^{}`));
      if (derefMatch) return derefMatch.split("\t")[0].trim();
      const match = lines.find((l) => l.endsWith(`\t${tag}`));
      if (match) return match.split("\t")[0].trim();
    }
  }
  die(`Could not resolve git SHA for ${version} in ${repoUrl}`);
}

async function getBrowsersJson(
  coreVersionKey: string,
  playwrightSha?: string,
): Promise<any> {
  // Fetch browsers.json from npm playwright-core tarball.
  try {
    const meta = await fetchJSON(
      `https://registry.npmjs.org/playwright-core/${coreVersionKey}`,
    );
    const tarballUrl = meta.dist?.tarball;
    if (tarballUrl) {
      log(
        `fetching package/browsers.json from npm playwright-core@${coreVersionKey}...`,
      );
      const tmpDir = fs.mkdtempSync(path.join("/tmp", "pw-core-"));
      try {
        const tarPath = path.join(tmpDir, "core.tgz");
        const curlRes = spawnSync("curl", ["-fsSL", tarballUrl, "-o", tarPath]);
        if (curlRes.status === 0) {
          const tarRes = spawnSync(
            "tar",
            ["-zxOf", tarPath, "package/browsers.json"],
            { encoding: "utf8" },
          );
          if (tarRes.status === 0 && tarRes.stdout) {
            return JSON.parse(tarRes.stdout);
          }
        }
      } finally {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      }
    }
  } catch {
    // Fall back to GitHub
  }

  if (playwrightSha) {
    log(`fetching browsers.json from GitHub raw at ${playwrightSha}...`);
    const browsersJsonUrl = `https://raw.githubusercontent.com/microsoft/playwright/${playwrightSha}/packages/playwright-core/browsers.json`;
    return await fetchJSON(browsersJsonUrl);
  }

  die(`Could not fetch browsers.json for core version ${coreVersionKey}`);
}

const SUPPORTED_BROWSERS = [
  "chromium",
  "chromium-headless-shell",
  "firefox",
  "webkit",
  "ffmpeg",
];

async function ensureBrowsers(
  coreVersionKey: string,
  lock: Lockfile,
  playwrightSha?: string,
) {
  if (lock.coreSets[coreVersionKey]) {
    log(
      `coreSet ${coreVersionKey} already exists in lockfile; reusing browser mapping.`,
    );
    return;
  }

  log(`resolving browsers for core key: ${coreVersionKey}`);
  const rawBrowsers = await getBrowsersJson(coreVersionKey, playwrightSha);

  const coreSet: Record<string, string> = {};

  for (const b of rawBrowsers.browsers) {
    if (b.installByDefault === false || !SUPPORTED_BROWSERS.includes(b.name)) {
      continue;
    }
    const name = b.name;
    const revision = String(b.revision);
    const browserVersion = b.browserVersion;

    coreSet[name] = revision;

    if (!lock.browsers[name]) lock.browsers[name] = {};
    if (lock.browsers[name][revision]) {
      log(`browser ${name}-${revision} already recorded; skipping prefetch.`);
      continue;
    }

    log(
      `new browser revision detected: ${name}-${revision}; prefetching hashes across platforms`,
    );
    const hashes: Record<string, string> = {};

    for (const sys of SUPPORTED_SYSTEMS) {
      const { url, stripRoot } = getBrowserUrl(
        name,
        revision,
        browserVersion,
        sys,
      );
      hashes[sys] = prefetchFetchzip(url, stripRoot);
    }

    const entry: any = { hashes };
    if (browserVersion) entry.browserVersion = browserVersion;
    lock.browsers[name][revision] = entry;
  }

  lock.coreSets[coreVersionKey] = coreSet;
}

// ==========================================
// Tool Sync Handlers
// ==========================================

async function syncCli(
  targetVersion?: string,
  lock: Lockfile = loadLockfile(),
) {
  log("syncing @playwright/cli...");
  const meta = await fetchJSON("https://registry.npmjs.org/@playwright/cli");
  const upstreamLatest = meta["dist-tags"]?.latest;
  const version = targetVersion || upstreamLatest;
  const isLatest = !targetVersion || targetVersion === upstreamLatest;

  if (lock.tools.cli.versions[version]) {
    log(`cli version ${version} already locked.`);
    if (isLatest) lock.tools.cli.latest = version;
    return;
  }

  const verMeta = await fetchJSON(
    `https://registry.npmjs.org/@playwright/cli/${version}`,
  );
  const pwVer =
    verMeta.dependencies?.playwright ||
    verMeta.dependencies?.["playwright-core"];
  if (!pwVer)
    die(`Cannot resolve playwright dependency for @playwright/cli@${version}`);

  const packageSha = resolveGitSha(
    "https://github.com/microsoft/playwright-cli.git",
    version,
    verMeta.gitHead,
  );

  await ensureBrowsers(pwVer, lock);

  const ghTarball = `https://github.com/microsoft/playwright-cli/archive/${packageSha}.tar.gz`;
  const srcHash = prefetchFile(ghTarball, true);
  const npmDepsHash = prefetchNpmDepsFromGithub(
    "microsoft",
    "playwright-cli",
    packageSha,
  );

  lock.tools.cli.versions[version] = {
    core: pwVer,
    packageSha,
    srcHash,
    npmDepsHash,
  };
  if (isLatest) lock.tools.cli.latest = version;
  log(`successfully locked cli@${version}`);
}

async function syncMcp(
  targetVersion?: string,
  lock: Lockfile = loadLockfile(),
) {
  log("syncing @playwright/mcp...");
  const meta = await fetchJSON("https://registry.npmjs.org/@playwright/mcp");
  const upstreamLatest = meta["dist-tags"]?.latest;
  const version = targetVersion || upstreamLatest;
  const isLatest = !targetVersion || targetVersion === upstreamLatest;

  if (lock.tools.mcp.versions[version]) {
    log(`mcp version ${version} already locked.`);
    if (isLatest) lock.tools.mcp.latest = version;
    return;
  }

  const verMeta = await fetchJSON(
    `https://registry.npmjs.org/@playwright/mcp/${version}`,
  );
  const pwVer =
    verMeta.dependencies?.playwright ||
    verMeta.dependencies?.["playwright-core"];
  if (!pwVer)
    die(`Cannot resolve playwright dependency for @playwright/mcp@${version}`);

  const packageSha = resolveGitSha(
    "https://github.com/microsoft/playwright-mcp.git",
    version,
    verMeta.gitHead,
  );

  await ensureBrowsers(pwVer, lock);

  const ghTarball = `https://github.com/microsoft/playwright-mcp/archive/${packageSha}.tar.gz`;
  const srcHash = prefetchFile(ghTarball, true);
  const npmDepsHash = prefetchNpmDepsFromGithub(
    "microsoft",
    "playwright-mcp",
    packageSha,
  );

  lock.tools.mcp.versions[version] = {
    core: pwVer,
    packageSha,
    srcHash,
    npmDepsHash,
  };
  if (isLatest) lock.tools.mcp.latest = version;
  log(`successfully locked mcp@${version}`);
}

async function syncNode(
  targetVersion?: string,
  lock: Lockfile = loadLockfile(),
) {
  log("syncing playwright (node)...");
  const meta = await fetchJSON("https://registry.npmjs.org/playwright");
  const upstreamLatest = meta["dist-tags"]?.latest;
  const version = targetVersion || upstreamLatest;
  const isLatest = !targetVersion || targetVersion === upstreamLatest;

  if (lock.tools.node.versions[version]) {
    log(`node version ${version} already locked.`);
    if (isLatest) lock.tools.node.latest = version;
    return;
  }

  const verMeta = await fetchJSON(
    `https://registry.npmjs.org/playwright/${version}`,
  );
  const coreVer = verMeta.dependencies?.["playwright-core"];
  if (!coreVer)
    die(`Cannot resolve playwright-core dependency for playwright@${version}`);

  const packageSha =
    verMeta.gitHead ||
    resolveGitSha("https://github.com/microsoft/playwright.git", version, null);

  await ensureBrowsers(coreVer, lock);

  const packageHash = prefetchFetchzip(verMeta.dist.tarball, true);
  const coreMeta = await fetchJSON(
    `https://registry.npmjs.org/playwright-core/${coreVer}`,
  );
  const coreHash = prefetchFetchzip(coreMeta.dist.tarball, true);

  lock.tools.node.versions[version] = {
    core: coreVer,
    packageSha,
    packageHash,
    coreHash,
  };
  if (isLatest) lock.tools.node.latest = version;
  log(`successfully locked node@${version}`);
}

async function syncDotnet(
  targetVersion?: string,
  lock: Lockfile = loadLockfile(),
) {
  log("syncing Microsoft.Playwright (dotnet)...");
  const flatMeta = await fetchJSON(
    "https://api.nuget.org/v3-flatcontainer/microsoft.playwright/index.json",
  );
  const stableVersions = flatMeta.versions.filter(
    (v: string) => !v.includes("-"),
  );
  const upstreamLatest = stableVersions[stableVersions.length - 1];
  const version = targetVersion || upstreamLatest;
  const isLatest = !targetVersion || targetVersion === upstreamLatest;

  if (lock.tools.dotnet.versions[version]) {
    log(`dotnet version ${version} already locked.`);
    if (isLatest) lock.tools.dotnet.latest = version;
    return;
  }

  const nupkgUrl = `https://api.nuget.org/v3-flatcontainer/microsoft.playwright/${version}/microsoft.playwright.${version}.nupkg`;
  const tmpDir = fs.mkdtempSync(path.join("/tmp", "pw-dotnet-"));
  let browsersJson: any;
  try {
    const nupkgPath = path.join(tmpDir, "pkg.nupkg");
    spawnSync("curl", ["-fsSL", nupkgUrl, "-o", nupkgPath]);
    const unzipRes = spawnSync(
      "unzip",
      ["-p", nupkgPath, ".playwright/package/browsers.json"],
      {
        encoding: "utf8",
      },
    );
    if (unzipRes.status !== 0 || !unzipRes.stdout) {
      die(`Could not extract browsers.json from ${nupkgUrl}`);
    }
    browsersJson = JSON.parse(unzipRes.stdout);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  const coreKey = `dotnet-${version}`;
  const coreSet: Record<string, string> = {};

  for (const b of browsersJson.browsers) {
    if (b.installByDefault === false || !SUPPORTED_BROWSERS.includes(b.name)) {
      continue;
    }
    const name = b.name;
    const revision = String(b.revision);
    const browserVersion = b.browserVersion;
    coreSet[name] = revision;

    if (!lock.browsers[name]) lock.browsers[name] = {};
    if (!lock.browsers[name][revision]) {
      log(`new browser revision detected in dotnet: ${name}-${revision}`);
      const hashes: Record<string, string> = {};
      for (const sys of SUPPORTED_SYSTEMS) {
        const { url, stripRoot } = getBrowserUrl(
          name,
          revision,
          browserVersion,
          sys,
        );
        hashes[sys] = prefetchFetchzip(url, stripRoot);
      }
      const entry: any = { hashes };
      if (browserVersion) entry.browserVersion = browserVersion;
      lock.browsers[name][revision] = entry;
    }
  }

  lock.coreSets[coreKey] = coreSet;
  const packageHash = prefetchFetchzip(nupkgUrl, false);

  lock.tools.dotnet.versions[version] = {
    core: coreKey,
    packageHash,
  };
  if (isLatest) lock.tools.dotnet.latest = version;
  log(`successfully locked dotnet@${version}`);
}

async function syncPython(
  targetVersion?: string,
  lock: Lockfile = loadLockfile(),
) {
  log("syncing playwright (python)...");
  const pypiMeta = await fetchJSON("https://pypi.org/pypi/playwright/json");
  const upstreamLatest = pypiMeta.info?.version;
  const version = targetVersion || upstreamLatest;
  const isLatest = !targetVersion || targetVersion === upstreamLatest;

  if (lock.tools.python.versions[version]) {
    log(`python version ${version} already locked.`);
    if (isLatest) lock.tools.python.latest = version;
    return;
  }

  // Resolve driver version
  let driverVersion = "";
  try {
    const driverVersionUrl = `https://raw.githubusercontent.com/microsoft/playwright-python/v${version}/DRIVER_VERSION`;
    const res = await fetch(driverVersionUrl);
    if (res.ok) driverVersion = (await res.text()).trim();
  } catch {}

  if (!driverVersion) {
    const setupPyUrl = `https://raw.githubusercontent.com/microsoft/playwright-python/v${version}/setup.py`;
    const setupText = await (await fetch(setupPyUrl)).text();
    const match = setupText.match(/driver_version\s*=\s*"([^"]+)"/);
    if (match) driverVersion = match[1];
  }
  if (!driverVersion)
    die(`Could not resolve driver_version for python playwright@${version}`);

  await ensureBrowsers(driverVersion, lock);

  const ghTarball = `https://github.com/microsoft/playwright-python/archive/v${version}.tar.gz`;
  const srcHash = prefetchFile(ghTarball, true);

  const driverHashes: Record<string, string> = {};
  for (const sys of SUPPORTED_SYSTEMS) {
    const driverZipName = {
      "x86_64-linux": "linux",
      "aarch64-linux": "linux-arm64",
      "aarch64-darwin": "mac-arm64",
    }[sys];
    const infix = driverVersion.includes("-") ? "next/" : "";
    const driverUrl = `https://cdn.playwright.dev/builds/driver/${infix}playwright-${driverVersion}-${driverZipName}.zip`;
    driverHashes[sys] = prefetchFetchzip(driverUrl, false);
  }

  lock.tools.python.versions[version] = {
    core: driverVersion,
    srcHash,
    driverHashes,
  };
  if (isLatest) lock.tools.python.latest = version;
  log(`successfully locked python@${version}`);
}

async function syncCamoufox(lock: Lockfile = loadLockfile()) {
  log("syncing camoufox...");
  // Python package
  const pypiMeta = await fetchJSON("https://pypi.org/pypi/camoufox/json");
  const latestPyPI = pypiMeta.info?.version;
  if (!lock.tools.camoufox.versions[latestPyPI]) {
    const sdist = pypiMeta.urls?.find((u: any) => u.packagetype === "sdist");
    if (sdist) {
      const hash = prefetchFile(sdist.url);
      lock.tools.camoufox.versions[latestPyPI] = {
        pypi: "camoufox",
        url: sdist.url,
        hash,
      };
      lock.tools.camoufox.latest = latestPyPI;
      log(`successfully locked camoufox@${latestPyPI}`);
    }
  }

  // Browser package
  const ghMeta = await fetchJSON(
    "https://api.github.com/repos/daijro/camoufox/releases/latest",
  );
  const tag = ghMeta.tag_name;
  const version = tag.replace(/^v/, "");
  if (!lock.tools["camoufox-browsers"].versions[version]) {
    const assetName = `camoufox-${version}-lin.arm64.zip`;
    const asset = ghMeta.assets?.find((a: any) => a.name === assetName);
    if (asset) {
      const hash = prefetchFetchzip(asset.browser_download_url, false);
      lock.tools["camoufox-browsers"].versions[version] = {
        tag,
        sources: {
          "aarch64-linux": {
            suffix: "lin.arm64",
            url: asset.browser_download_url,
            hash,
          },
        },
      };
      lock.tools["camoufox-browsers"].latest = version;
      log(`successfully locked camoufox-browsers@${version}`);
    }
  }
}

// ==========================================
// CLI Entry Point
// ==========================================

async function main() {
  const args = process.argv.slice(2);
  const lock = loadLockfile();

  if (args.length === 0) {
    log("starting sync for all tools...");
    await syncCli(undefined, lock);
    await syncMcp(undefined, lock);
    await syncNode(undefined, lock);
    await syncDotnet(undefined, lock);
    await syncPython(undefined, lock);
    await syncCamoufox(lock);
    saveLockfile(lock);
    log("all tools synchronized successfully.");
    return;
  }

  const tool = args[0];
  const version = args[1];

  switch (tool) {
    case "cli":
      await syncCli(version, lock);
      break;
    case "mcp":
      await syncMcp(version, lock);
      break;
    case "node":
      await syncNode(version, lock);
      break;
    case "dotnet":
      await syncDotnet(version, lock);
      break;
    case "python":
      await syncPython(version, lock);
      break;
    case "camoufox":
      await syncCamoufox(lock);
      break;
    default:
      die(
        `Unknown tool: ${tool}. Expected cli|mcp|node|dotnet|python|camoufox`,
      );
  }

  saveLockfile(lock);
}

main().catch((err) => {
  die(err.stack || String(err));
});
