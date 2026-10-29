import { createRemoteJWKSet, jwtVerify } from "jose";

import { renderMapPage, renderNotFoundPage } from "./page";

/**
 * Townloader 지도 공유 · 동기화 Worker.
 *
 * 로그인
 *   POST   /api/session   { "provider": "google" | "apple", "idToken": "..." }
 *          -> { "token": "<세션 토큰>", "user": { "email": "..." } }
 *   DELETE /api/session   지금 세션을 끝낸다.
 *   DELETE /api/account   계정과 동기화한 링크, 공유한 지도를 모두 지운다.
 *
 * 동기화 (Authorization: Bearer <세션 토큰>)
 *   GET    /api/data      -> { "data": { "categories": [...], "links": [...] } | null, "updatedAt": 0 }
 *   PUT    /api/data      { "categories": [...], "links": [...] }
 *
 * 공유
 *   GET    /api/shares               -> { "shares": [{ "id", "category", "url" }] }
 *   POST   /api/shares { category }  카테고리를 public 으로 바꾸고 링크를 준다. 이미 있으면 그대로.
 *   DELETE /api/shares/<id>          다시 비공개로.
 *
 * 공개
 *   GET /m/<id>        웹 지도. 앱이 깔려 있으면 Universal Link · App Link 로 앱이 연다.
 *   GET /m/<id>.json   앱이 그리는 공개 데이터. 글(사진·해시태그를 뺀 캡션)과 장소를 담는다.
 *   GET /.well-known/apple-app-site-association, /.well-known/assetlinks.json
 */

export interface Env {
  DB: D1Database;
  GOOGLE_CLIENT_IDS: string;
  APPLE_BUNDLE_ID: string;
  APPLE_APP_ID: string;
  ANDROID_PACKAGE: string;
  ANDROID_CERT_SHA256: string;
  APP_STORE_URL: string;
  PLAY_STORE_URL: string;
  /** 웹 지도의 Mapbox 공개 토큰(`pk.`). secret 으로 넣는다. 없으면 OpenStreetMap 타일을 쓴다. */
  MAPBOX_TOKEN?: string;
}

const SESSION_DAYS = 180;
/** 동기화 한 번에 받는 최대 크기. 링크 수천 개도 들어간다. */
const MAX_DATA_BYTES = 2 * 1024 * 1024;

const googleKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: error.code }, error.status);
      }
      console.error(error);
      return json({ error: "server_error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  if (method === "GET" && path === "/.well-known/apple-app-site-association") {
    return json(appleAppSiteAssociation(env));
  }
  if (method === "GET" && path === "/.well-known/assetlinks.json") {
    return json(assetLinks(env));
  }

  const share = /^\/m\/([A-Za-z0-9]{6,32})(\.json)?$/.exec(path);
  if (method === "GET" && share) {
    const map = await publicMap(env, share[1]);
    if (share[2]) {
      return map ? json(map) : json({ error: "not_found" }, 404);
    }
    const stores = { appStore: env.APP_STORE_URL, playStore: env.PLAY_STORE_URL };
    return html(
      map
        ? renderMapPage(map, url.href, stores, env.MAPBOX_TOKEN ?? "")
        : renderNotFoundPage(stores),
      map ? 200 : 404,
    );
  }

  if (path === "/api/session" && method === "POST") return signIn(request, env);

  if (!path.startsWith("/api/")) return json({ error: "not_found" }, 404);
  const session = await authenticate(request, env);

  if (path === "/api/session" && method === "DELETE") {
    await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?")
      .bind(session.tokenHash)
      .run();
    return json({ ok: true });
  }
  if (path === "/api/account" && method === "DELETE") {
    await deleteAccount(env, session.userId);
    return json({ ok: true });
  }
  if (path === "/api/data" && method === "GET") return getData(env, session.userId);
  if (path === "/api/data" && method === "PUT") {
    return putData(request, env, session.userId);
  }
  if (path === "/api/shares" && method === "GET") {
    return json({ shares: await listShares(env, session.userId, url.origin) });
  }
  if (path === "/api/shares" && method === "POST") {
    return createShare(request, env, session.userId, url.origin);
  }
  const unshare = /^\/api\/shares\/([A-Za-z0-9]{6,32})$/.exec(path);
  if (unshare && method === "DELETE") {
    await env.DB.prepare("DELETE FROM shares WHERE id = ? AND user_id = ?")
      .bind(unshare[1], session.userId)
      .run();
    return json({ ok: true });
  }
  return json({ error: "not_found" }, 404);
}

// ── 로그인 ──────────────────────────────────────────────────────────────────

async function signIn(request: Request, env: Env): Promise<Response> {
  const body = (await request.json().catch(() => null)) as {
    provider?: unknown;
    idToken?: unknown;
  } | null;
  if (typeof body?.idToken !== "string") throw new HttpError(400, "bad_request");

  let provider: "google" | "apple";
  let subject: string;
  let email: string | null;
  try {
    if (body.provider === "google") {
      const audience = env.GOOGLE_CLIENT_IDS.split(",")
        .map((id) => id.trim())
        .filter(Boolean);
      if (audience.length === 0) throw new HttpError(503, "google_not_configured");
      const { payload } = await jwtVerify(body.idToken, googleKeys, {
        issuer: ["https://accounts.google.com", "accounts.google.com"],
        audience,
      });
      provider = "google";
      subject = String(payload.sub);
      email = typeof payload.email === "string" ? payload.email : null;
    } else if (body.provider === "apple") {
      const { payload } = await jwtVerify(body.idToken, appleKeys, {
        issuer: "https://appleid.apple.com",
        audience: env.APPLE_BUNDLE_ID,
      });
      provider = "apple";
      subject = String(payload.sub);
      email = typeof payload.email === "string" ? payload.email : null;
    } else {
      throw new HttpError(400, "bad_provider");
    }
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(401, "invalid_token");
  }

  const now = Date.now();
  // Apple 은 이메일을 처음 로그인할 때만 주므로, 없으면 예전 값을 남긴다.
  const user = await env.DB.prepare(
    `INSERT INTO users (id, provider, subject, email, created_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT (provider, subject) DO UPDATE SET email = COALESCE(excluded.email, users.email)
     RETURNING id, email`,
  )
    .bind(crypto.randomUUID(), provider, subject, email, now)
    .first<{ id: string; email: string | null }>();
  if (!user) throw new HttpError(500, "user_failed");

  const token = randomId(40);
  await env.DB.prepare(
    "INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
  )
    .bind(await sha256(token), user.id, now, now + SESSION_DAYS * 86400_000)
    .run();
  return json({ token, user: { email: user.email, provider } });
}

async function authenticate(
  request: Request,
  env: Env,
): Promise<{ userId: string; tokenHash: string }> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) throw new HttpError(401, "unauthorized");
  const tokenHash = await sha256(token);
  const row = await env.DB.prepare(
    "SELECT user_id, expires_at FROM sessions WHERE token_hash = ?",
  )
    .bind(tokenHash)
    .first<{ user_id: string; expires_at: number }>();
  if (!row || row.expires_at < Date.now()) throw new HttpError(401, "unauthorized");
  return { userId: row.user_id, tokenHash };
}

async function deleteAccount(env: Env, userId: string): Promise<void> {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM shares WHERE user_id = ?").bind(userId),
    env.DB.prepare("DELETE FROM user_data WHERE user_id = ?").bind(userId),
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(userId),
    env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId),
  ]);
}

// ── 동기화 ──────────────────────────────────────────────────────────────────

interface LinksData {
  categories: string[];
  links: SavedLink[];
}

interface SavedLink {
  code: string;
  url: string;
  category: string;
  title?: string | null;
  author?: string | null;
  caption?: string | null;
  coverUrl?: string | null;
  imageUrls?: string[];
  places?: {
    name: string;
    lat: number;
    lng: number;
    address?: string | null;
    category?: string | null;
    phone?: string | null;
    photoUrl?: string | null;
    placeUrl?: string | null;
    rating?: number | null;
    reviewCount?: number | null;
    approximate?: boolean;
    imageIndex?: number | null;
  }[];
}

async function getData(env: Env, userId: string): Promise<Response> {
  const row = await env.DB.prepare(
    "SELECT data, updated_at FROM user_data WHERE user_id = ?",
  )
    .bind(userId)
    .first<{ data: string; updated_at: number }>();
  return json({
    data: row ? JSON.parse(row.data) : null,
    updatedAt: row?.updated_at ?? 0,
  });
}

async function putData(request: Request, env: Env, userId: string): Promise<Response> {
  const text = await request.text();
  if (text.length > MAX_DATA_BYTES) throw new HttpError(413, "too_large");
  let data: LinksData;
  try {
    data = JSON.parse(text);
  } catch {
    throw new HttpError(400, "bad_request");
  }
  if (!Array.isArray(data?.categories) || !Array.isArray(data?.links)) {
    throw new HttpError(400, "bad_request");
  }
  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO user_data (user_id, data, updated_at) VALUES (?, ?, ?)
     ON CONFLICT (user_id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
  )
    .bind(userId, text, now)
    .run();
  return json({ ok: true, updatedAt: now });
}

// ── 공유 ────────────────────────────────────────────────────────────────────

async function listShares(env: Env, userId: string, origin: string) {
  const { results } = await env.DB.prepare(
    "SELECT id, category FROM shares WHERE user_id = ? ORDER BY created_at",
  )
    .bind(userId)
    .all<{ id: string; category: string }>();
  return results.map((row) => ({ ...row, url: `${origin}/m/${row.id}` }));
}

async function createShare(
  request: Request,
  env: Env,
  userId: string,
  origin: string,
): Promise<Response> {
  const body = (await request.json().catch(() => null)) as { category?: unknown } | null;
  const category = typeof body?.category === "string" ? body.category.trim() : "";
  if (!category || category.length > 100) throw new HttpError(400, "bad_request");

  const row = await env.DB.prepare(
    `INSERT INTO shares (id, user_id, category, created_at) VALUES (?, ?, ?, ?)
     ON CONFLICT (user_id, category) DO UPDATE SET category = excluded.category
     RETURNING id, category`,
  )
    .bind(randomId(10), userId, category, Date.now())
    .first<{ id: string; category: string }>();
  if (!row) throw new HttpError(500, "share_failed");
  return json({ ...row, url: `${origin}/m/${row.id}` });
}

export interface PublicPlace {
  name: string;
  address: string | null;
  category?: string | null;
  phone?: string | null;
  placeUrl?: string | null;
  rating?: number | null;
  reviewCount?: number | null;
  lat: number;
  lng: number;
  approximate: boolean;
  url: string;
  author: string | null;
  /** 이 장소가 나온 사진. 없으면 글의 대표 사진. */
  photo: string | null;
  /** [PublicMap.posts] 에서 이 장소가 속한 글의 순번. */
  post: number;
}

export interface PublicPost {
  url: string;
  /** 앱이 지은 짧은 대표 제목. */
  title: string | null;
  author: string | null;
  /** 해시태그를 뺀 캡션. */
  caption: string | null;
  coverUrl: string | null;
  imageUrls: string[];
  /** 이 글의 장소들. [PublicMap.places] 의 순번이다. */
  places: number[];
}

/** 공개 지도에 내보내는 모양. 인스타그램 사진 주소는 시간이 지나면 만료된다. */
export interface PublicMap {
  id: string;
  category: string;
  updatedAt: number;
  posts: PublicPost[];
  places: PublicPlace[];
}

/** 캡션에서 해시태그를 지우고, 그 때문에 빈 줄이 된 곳을 정리한다. */
export function cleanCaption(caption: string | null | undefined): string | null {
  if (!caption) return null;
  const text = caption
    .replace(/(^|\s)#[^\s#]+/gu, "$1")
    .split("\n")
    .map((line) => line.replace(/[ \t\u3000]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!text) return null;
  return text.length > 1200 ? `${text.slice(0, 1200).trimEnd()}…` : text;
}

const PHOTO_URL = /^https:\/\/[^/]*(cdninstagram\.com|fbcdn\.net|kakaocdn\.net)\//;

function photoUrl(value: unknown): string | null {
  return typeof value === "string" && PHOTO_URL.test(value) ? value : null;
}

async function publicMap(env: Env, id: string): Promise<PublicMap | null> {
  const row = await env.DB.prepare(
    `SELECT shares.category AS category, user_data.data AS data, user_data.updated_at AS updated_at
     FROM shares LEFT JOIN user_data ON user_data.user_id = shares.user_id
     WHERE shares.id = ?`,
  )
    .bind(id)
    .first<{ category: string; data: string | null; updated_at: number | null }>();
  if (!row) return null;

  const data: LinksData = row.data ? JSON.parse(row.data) : { categories: [], links: [] };
  const posts: PublicPost[] = [];
  const places: PublicPlace[] = [];
  for (const link of data.links ?? []) {
    if (link.category !== row.category) continue;
    if (!/^https:\/\/(www\.)?instagram\.com\//.test(link.url)) continue;
    const coverUrl = photoUrl(link.coverUrl);
    const imageUrls = (link.imageUrls ?? []).map(photoUrl).filter((url): url is string => !!url);
    const post: PublicPost = {
      url: link.url,
      title: typeof link.title === "string" ? link.title.slice(0, 60) : null,
      author: link.author ?? null,
      caption: cleanCaption(link.caption),
      coverUrl: coverUrl ?? imageUrls[0] ?? null,
      imageUrls,
      places: [],
    };
    for (const place of link.places ?? []) {
      if (typeof place.lat !== "number" || typeof place.lng !== "number") continue;
      const index = place.imageIndex;
      const slidePhoto =
        typeof index === "number" && index >= 0 && index < (link.imageUrls?.length ?? 0)
          ? photoUrl(link.imageUrls![index])
          : null;
      const kakaoPhoto = photoUrl(place.photoUrl);
      post.places.push(places.length);
      places.push({
        name: String(place.name ?? ""),
        address: place.address ?? null,
        category: place.category ?? null,
        phone: place.phone ?? null,
        placeUrl: place.placeUrl ?? null,
        rating: typeof place.rating === "number" ? place.rating : null,
        reviewCount: typeof place.reviewCount === "number" ? place.reviewCount : null,
        lat: place.lat,
        lng: place.lng,
        approximate: place.approximate === true,
        url: link.url,
        author: link.author ?? null,
        photo: kakaoPhoto ?? slidePhoto ?? post.coverUrl,
        post: posts.length,
      });
    }
    // 장소를 못 찾은 글도 목록에는 보여 준다.
    posts.push(post);
  }
  return { id, category: row.category, updatedAt: row.updated_at ?? 0, posts, places };
}

// ── 딥링크 검증 파일 ────────────────────────────────────────────────────────

function appleAppSiteAssociation(env: Env) {
  return {
    applinks: {
      details: [{ appIDs: [env.APPLE_APP_ID], components: [{ "/": "/m/*" }] }],
    },
  };
}

function assetLinks(env: Env) {
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: env.ANDROID_PACKAGE,
        sha256_cert_fingerprints: env.ANDROID_CERT_SHA256.split(",")
          .map((value) => value.trim())
          .filter(Boolean),
      },
    },
  ];
}

// ── 도구 ────────────────────────────────────────────────────────────────────

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

function randomId(length: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}
