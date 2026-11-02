// 요약 A/B 테스트의 평가를 공급자·모델별로 센다.
//   npm run ab-stats              배포된 KV 를 읽는다.
//   npm run ab-stats -- --local   wrangler dev 의 로컬 KV 를 읽는다.
import { execFileSync } from "node:child_process";

const AB_VERSION = "v1";
const extra = process.argv.slice(2);
const target = extra.includes("--local") ? extra : ["--remote", ...extra];

const output = execFileSync(
  "npx",
  [
    "wrangler", "kv", "key", "list",
    "--binding", "SUMMARIES",
    ...target,
    "--prefix", `vote:${AB_VERSION}:`,
  ],
  { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"], maxBuffer: 256 * 1024 * 1024 },
);

const rows = new Map();
for (const { name, metadata } of JSON.parse(output)) {
  const [, , provider] = name.split(":");
  const label = `${provider} / ${metadata?.model || "?"}`;
  const row = rows.get(label) ?? { up: 0, down: 0 };
  if (metadata?.vote === "up") row.up += 1;
  if (metadata?.vote === "down") row.down += 1;
  rows.set(label, row);
}

if (rows.size === 0) console.log("아직 평가가 없습니다.");
for (const [label, { up, down }] of [...rows].sort()) {
  const total = up + down;
  const rate = total === 0 ? "-" : `${Math.round((up / total) * 100)}%`;
  console.log(`${label}: 👍 ${up}  👎 ${down}  (좋아요 ${rate}, ${total}건)`);
}
