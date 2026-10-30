import { AsyncLocalStorage } from "node:async_hooks";

/**
 * 요청 하나가 바깥 유료 서비스를 몇 번 불렀는지 센다.
 *
 * 전역 fetch 를 한 번 감싸서 주소(와 요청 본문의 model)로 서비스를 가린다. 세는 곳을
 * 호출마다 따로 적지 않아도, 새로 더한 호출까지 빠짐없이 잡힌다. 결과는 응답의
 * `x-usage` 헤더({"jev":2,"kakao":7})로 앱에 넘기고, 앱이 서비스별 가중치를 곱해
 * 토큰으로 계산한다. 캐시에서 돌려준 응답은 아무것도 부르지 않았으니 헤더가 없다.
 */
export type Usage = Record<string, number>;

const store = new AsyncLocalStorage<Usage>();
let installed = false;

export function installUsageMeter(): void {
  if (installed) return;
  installed = true;
  const original = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const usage = store.getStore();
    if (usage) {
      const key = classify(input, init);
      if (key) usage[key] = (usage[key] ?? 0) + 1;
    }
    return original(input, init);
  }) as typeof fetch;
}

/** [run] 이 부른 횟수를 모아 함께 돌려준다. */
export async function withUsage<T>(run: () => Promise<T>): Promise<{ result: T; usage: Usage }> {
  const usage: Usage = {};
  const result = await store.run(usage, run);
  return { result, usage };
}

/** 따로 실행된 Worker(장소 좌표 찾기)가 센 것을 지금 요청에 더한다. */
export function addUsage(header: string | null): void {
  const usage = store.getStore();
  if (!usage || !header) return;
  try {
    const other = JSON.parse(header) as Usage;
    for (const [key, count] of Object.entries(other)) {
      if (Number.isFinite(count)) usage[key] = (usage[key] ?? 0) + count;
    }
  } catch {}
}

function classify(input: RequestInfo | URL, init?: RequestInit): string | null {
  let host: string;
  try {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    host = new URL(url).hostname;
  } catch {
    return null;
  }
  const body = typeof init?.body === "string" ? init.body : "";
  const model = /"model"\s*:\s*"([^"]+)"/.exec(body)?.[1] ?? "";
  if (host === "api.typesafe.ai") return "jev";
  if (host === "api.anthropic.com") return /haiku/i.test(model) ? "claude_haiku" : "claude";
  if (host === "api.poe.com") return /elevenlabs|tts/i.test(model) ? "poe_tts" : "poe";
  if (host === "kakao.com" || host.endsWith(".kakao.com")) return "kakao";
  if (host === "mapbox.com" || host.endsWith(".mapbox.com")) return "mapbox";
  return null;
}
