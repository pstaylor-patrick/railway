// Renders docs/hero.gif: a terminal session typing a few railway commands.
// Output is canned with placeholder names so no real project data is shown.
// Frames are rendered by index, not wall clock, so the output is deterministic.
//
// Run from the repo root (needs ffmpeg on PATH):
//   npx -y -p playwright@1.63.0 node scripts/hero-gif.mjs
//
// playwright@1.63.0 uses chromium revision 1243; install it once with
//   npx -y playwright@1.63.0 install chromium
/* global window, document */
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const out = join(root, "docs/hero.gif");

const WIDTH = 720;
const HEIGHT = 420;
const FPS = 15;
const CHARS_PER_FRAME = 2;
const PAUSE_AFTER_CMD = 6;
const HOLD_AFTER_OUTPUT = 22;
const FINAL_HOLD = 30;

// Each scene clears the screen, types `cmd`, then prints `out`.
// Output lines may start with a style tag: "!" muted, "+" ok, "-" error.
const SCENES = [
  {
    cmd: "railway whoami",
    out: [
      "bearer: RAILWAY_PAT_ACCOUNT -> account",
      "!  Ada Lovelace <ada@example.com>",
      "project: RAILWAY_PAT_PROJECT -> project",
    ],
  },
  {
    cmd: "railway status --project my-app",
    out: [
      "!environment: production",
      "!SERVICE   STATUS    CREATED               DOMAIN",
      "+api       SUCCESS   2026-01-01T09:00:00Z  api.example.com",
      "+worker    SUCCESS   2026-01-01T09:02:11Z  -",
      "-web       FAILED    2026-01-01T09:04:37Z  web.example.com",
    ],
  },
  {
    cmd: "railway vars --project my-app --env production --service api",
    out: ["DATABASE_URL     po****", "STRIPE_KEY       sk****"],
  },
  {
    cmd: "railway env delete preview --project my-app",
    out: ["-error: no TTY: pass --confirm <exact environment name>"],
  },
  {
    cmd: "railway env delete preview --project my-app --confirm preview",
    out: ["+deleted  preview", "!dashboard: https://railway.com/project/..."],
  },
];

const timeline = [];
for (const [i, s] of SCENES.entries()) {
  const typeFrames = Math.ceil(s.cmd.length / CHARS_PER_FRAME);
  const hold = i === SCENES.length - 1 ? FINAL_HOLD : HOLD_AFTER_OUTPUT;
  timeline.push({ scene: i, typeFrames, frames: typeFrames + PAUSE_AFTER_CMD + hold });
}
const TOTAL = timeline.reduce((n, t) => n + t.frames, 0);

// `npx -p playwright` puts its node_modules/.bin on PATH but ESM imports do not
// search there, so resolve playwright from those PATH entries.
const binDirs = (process.env.PATH ?? "").split(":").filter((d) => d.endsWith("node_modules/.bin"));
const bases = [process.cwd(), ...binDirs.map((d) => join(d, "..", ".."))];
const require = createRequire(join(root, "noop.js"));
const { chromium } = require(require.resolve("playwright", { paths: bases }));

const html = `<!doctype html>
<html><head><style>
  html, body { margin: 0; width: ${WIDTH}px; height: ${HEIGHT}px; overflow: hidden;
               background: radial-gradient(circle at 30% 0%, #2a1a40, #0e0b14 70%); }
  .win { position: absolute; inset: 28px; border-radius: 12px; background: #13101b;
         border: 1px solid #2c2340; box-shadow: 0 18px 40px rgba(0,0,0,.5); overflow: hidden; }
  .bar { height: 30px; display: flex; align-items: center; gap: 7px; padding: 0 12px;
         background: #1b1726; border-bottom: 1px solid #2c2340; }
  .dot { width: 11px; height: 11px; border-radius: 50%; }
  .title { margin-left: 10px; color: #8b84a0; font: 12px ui-monospace, Menlo, monospace; }
  pre { margin: 0; padding: 14px 16px; color: #e6e1f2; white-space: pre-wrap;
        font: 13.5px/1.55 "DejaVu Sans Mono", ui-monospace, Menlo, monospace; }
  .p { color: #a970ff; } .m { color: #8b84a0; } .ok { color: #5fd38d; } .err { color: #ff6b81; }
  .cur { display: inline-block; width: 8px; height: 15px; background: #a970ff; vertical-align: -2px; }
</style></head><body>
  <div class="win">
    <div class="bar"><span class="dot" style="background:#ff5f57"></span><span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span><span class="title">railway - personal CLI on the Railway GraphQL API</span></div>
    <pre id="t"></pre>
  </div>
  <script>
    const SCENES = ${JSON.stringify(SCENES)};
    const TIMELINE = ${JSON.stringify(timeline)};
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const styled = (l) => {
      const cls = { "!": "m", "+": "ok", "-": "err" }[l[0]];
      return cls ? '<span class="' + cls + '">' + esc(l.slice(1)) + "</span>" : esc(l);
    };
    window.render = (frame) => {
      let f = frame, t = TIMELINE[0];
      for (t of TIMELINE) { if (f < t.frames) break; f -= t.frames; }
      const s = SCENES[t.scene];
      const typed = s.cmd.slice(0, f * ${CHARS_PER_FRAME});
      const done = f >= t.typeFrames + ${PAUSE_AFTER_CMD};
      let html = '<span class="p">$</span> ' + esc(typed);
      if (done) html += "\\n" + s.out.map(styled).join("\\n") + '\\n<span class="p">$</span> ';
      html += '<span class="cur"></span>';
      document.getElementById("t").innerHTML = html;
    };
  </script>
</body></html>`;

const dir = mkdtempSync(join(tmpdir(), "railway-hero-"));
let browser;
try {
  browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } });
  await page.setContent(html);
  for (let i = 0; i < TOTAL; i++) {
    await page.evaluate((f) => window.render(f), i);
    await page.screenshot({ path: join(dir, `f${String(i).padStart(4, "0")}.png`) });
  }
  await browser.close();
  browser = undefined;

  const input = ["-framerate", String(FPS), "-i", join(dir, "f%04d.png")];
  const palette = join(dir, "palette.png");
  execFileSync("ffmpeg", ["-v", "error", "-y", ...input, "-vf", "palettegen=stats_mode=diff:max_colors=64", palette]);
  execFileSync("ffmpeg", [
    "-v", "error", "-y", ...input, "-i", palette,
    "-lavfi", "paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle",
    "-loop", "0", out,
  ]);
} finally {
  await browser?.close();
  rmSync(dir, { recursive: true, force: true });
}

console.log(`wrote ${out}: ${TOTAL} frames, ${statSync(out).size} bytes`);
