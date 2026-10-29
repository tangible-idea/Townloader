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

  const placeDetail = /^\/api\/place\/(\d{3,20})$/.exec(path);
  if (method === "GET" && placeDetail) {
    return handlePlaceDetail(placeDetail[1]);
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
    summary?: string | null;
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
  kakaoId?: string | null;
  rating?: number | null;
  reviewCount?: number | null;
  summary?: string | null;
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
  const isPostShare = row.category.startsWith("post:");
  const targetCode = isPostShare ? row.category.slice("post:".length) : null;
  const matchedLinks = (data.links ?? []).filter((link) =>
    isPostShare ? link.code === targetCode : link.category === row.category,
  );
  if (isPostShare && matchedLinks.length === 0) return null;

  const firstLink = matchedLinks[0];
  const displayCategory = isPostShare
    ? firstLink?.title ||
      (firstLink?.author ? `@${firstLink.author}` : firstLink?.category || "Townloader")
    : row.category;

  const posts: PublicPost[] = [];
  const places: PublicPlace[] = [];
  for (const link of matchedLinks) {
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
    const enrichedPlaces = await Promise.all(
      (link.places ?? []).map(async (place) => {
        if (typeof place.lat !== "number" || typeof place.lng !== "number") return null;
        if (!place.photoUrl && !place.category && !place.placeUrl && !place.approximate) {
          const hit = await searchKakaoPlace(place.name, place.address ?? null);
          if (hit) {
            return {
              ...place,
              address: place.address ?? hit.address,
              category: hit.category,
              phone: hit.phone,
              photoUrl: hit.photoUrl,
              placeUrl: hit.placeUrl,
              rating: hit.rating,
              reviewCount: hit.reviewCount,
            };
          }
        }
        return place;
      }),
    );
    for (const place of enrichedPlaces) {
      if (!place) continue;
      const index = place.imageIndex;
      const slidePhoto =
        typeof index === "number" && index >= 0 && index < (link.imageUrls?.length ?? 0)
          ? photoUrl(link.imageUrls![index])
          : null;
      const kakaoPhoto = photoUrl(place.photoUrl);
      const placeUrl = typeof place.placeUrl === "string" ? place.placeUrl : null;
      const idMatch = placeUrl ? /place\.map\.kakao\.com\/(\d+)/.exec(placeUrl) : null;
      post.places.push(places.length);
      places.push({
        name: String(place.name ?? ""),
        address: place.address ?? null,
        category: place.category ?? null,
        phone: place.phone ?? null,
        placeUrl,
        kakaoId: idMatch ? idMatch[1] : null,
        rating: typeof place.rating === "number" ? place.rating : null,
        reviewCount: typeof place.reviewCount === "number" ? place.reviewCount : null,
        summary: typeof place.summary === "string" ? place.summary : null,
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
  return { id, category: displayCategory, updatedAt: row.updated_at ?? 0, posts, places };
}

// ── 카카오맵 장소 검색 · 상세 패널 프록시 ────────────────────────────────────

function kakaoThumb(rawUrl: unknown): string | null {
  if (typeof rawUrl !== "string" || !rawUrl.trim()) return null;
  const httpsUrl = rawUrl.trim().replace(/^http:\/\//, "https://");
  return `https://img1.kakaocdn.net/cthumb/local/R400x0/?fname=${encodeURIComponent(httpsUrl)}`;
}

async function searchKakaoPlace(name: string, address: string | null) {
  try {
    const words = String(name ?? "").trim().split(/\s+/).filter(Boolean);
    const variants: string[] = [];
    for (let n = words.length; n >= 1; n--) {
      const q = words.slice(0, n).join(" ");
      if (q.replace(/\s/g, "").length >= 2) variants.push(q);
    }
    const area = (address ?? "")
      .split(/\s+/)
      .filter((w) => /(동|읍|면|리|가|구|군)$/.test(w) || /동\d*가$/.test(w))
      .reverse();
    const norm = (s: string) => s.toLowerCase().replace(/[\s\p{P}\p{S}]/gu, "");
    for (const q of variants) {
      const url =
        "https://search.map.kakao.com/mapsearch/map.daum?callback=j&msFlag=A&sort=0&q=" +
        encodeURIComponent(q);
      const res = await fetch(url, {
        headers: { referer: "https://map.kakao.com/", "user-agent": "Mozilla/5.0" },
      });
      if (!res.ok) continue;
      const text = await res.text();
      const s = text.indexOf("(");
      const e = text.lastIndexOf(")");
      if (s < 0 || e <= s) continue;
      const parsed = JSON.parse(text.slice(s + 1, e)) as { place?: Record<string, any>[] };
      for (const p of parsed.place ?? []) {
        const a = norm(q);
        const b = norm(String(p.name ?? ""));
        if (!a || !b || (!a.includes(b) && !b.includes(a))) continue;
        const fullAddr = `${p.address ?? ""} ${p.new_address ?? ""}`;
        if (area.length > 0 && !area.some((t) => fullAddr.includes(t))) continue;
        const rawImg =
          p.img ||
          (Array.isArray(p.image_info?.image_main_urls) ? p.image_info.image_main_urls[0] : null);
        const rating = Number(p.rating_average);
        const reviews = Number(p.reviewCount) || Number(p.rating_count);
        const cid = String(p.confirmid ?? "").trim();
        return {
          address: String(p.new_address || p.address || "").trim() || null,
          category: String(p.last_cate_name || p.cate_name_depth2 || "").trim() || null,
          phone: String(p.tel || "").trim() || null,
          photoUrl: kakaoThumb(rawImg),
          placeUrl: cid ? `https://place.map.kakao.com/${cid}` : null,
          rating: Number.isFinite(rating) && rating > 0 ? rating : null,
          reviewCount: Number.isFinite(reviews) && reviews > 0 ? reviews : null,
        };
      }
    }
    return null;
  } catch {
    return null;
  }
}

async function handlePlaceDetail(confirmId: string): Promise<Response> {
  try {
    const res = await fetch(`https://place-api.map.kakao.com/places/panel3/${confirmId}`, {
      headers: {
        referer: `https://place.map.kakao.com/${confirmId}`,
        "user-agent": "Mozilla/5.0",
        accept: "application/json",
        pf: "web",
      },
    });
    if (!res.ok) return json({ error: "upstream_error" }, 502);
    const raw = (await res.json()) as Record<string, any>;
    const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

    const aiMate = raw.ai_mate ?? {};
    const aiTitle = str(aiMate.summary?.title) ?? str(aiMate.bottom_sheet?.title);
    const aiSummary = str(aiMate.bottom_sheet?.summary);
    const priceLevel = str(aiMate.price_level?.symbol);
    const aiKeywords: string[] = [];
    for (const g of Array.isArray(aiMate.blog_summaries) ? aiMate.blog_summaries : []) {
      for (const kw of Array.isArray(g?.keywords) ? g.keywords : []) {
        const k = str(kw);
        if (k && !aiKeywords.includes(k)) aiKeywords.push(k);
      }
    }

    const hours = raw.open_hours ?? {};
    const openParts = [
      str(hours.headline?.display_text),
      str(hours.headline?.display_text_info),
    ].filter(Boolean);
    const openStatus = openParts.length > 0 ? openParts.join(" · ") : null;
    const openHours: string[] = [];
    for (const period of Array.isArray(hours.week_from_today?.week_periods)
      ? hours.week_from_today.week_periods
      : []) {
      for (const day of Array.isArray(period?.days) ? period.days : []) {
        const label = str(day?.day_of_the_week_desc);
        if (!label) continue;
        const time = str(day?.on_days?.start_end_time_desc) ?? str(day?.off_days_desc) ?? "휴무";
        const lastOrder = Array.isArray(day?.on_days?.last_order_times_desc)
          ? str(day.on_days.last_order_times_desc[0])
          : null;
        openHours.push([label, time, lastOrder ? `(${lastOrder})` : null].filter(Boolean).join(" "));
      }
    }

    const photos: string[] = [];
    for (const item of (Array.isArray(raw.photos?.photos) ? raw.photos.photos : []).slice(0, 10)) {
      const thumb = kakaoThumb(item?.url);
      if (thumb && !photos.includes(thumb)) photos.push(thumb);
    }

    const menus = (Array.isArray(raw.menu?.menus?.items) ? raw.menu.menus.items : [])
      .slice(0, 8)
      .map((m: any) => ({
        name: str(m?.name),
        price: Number.isFinite(Number(m?.price)) ? Number(m.price) : null,
        description: str(m?.desc),
        recommend: m?.is_recommend === true,
      }))
      .filter((m: any) => m.name);

    const tags = (Array.isArray(raw.place_add_info?.tags) ? raw.place_add_info.tags : [])
      .slice(0, 10)
      .map(str)
      .filter(Boolean);

    const kRev = raw.kakaomap_review ?? {};
    const descById = new Map<number, string>();
    for (const d of Array.isArray(kRev.strength_description) ? kRev.strength_description : []) {
      const id = Number(d?.id);
      const name = str(d?.name);
      if (Number.isFinite(id) && name) descById.set(id, name);
    }
    const strengths = (Array.isArray(kRev.score_set?.strength_counts)
      ? kRev.score_set.strength_counts
      : []
    )
      .map((c: any) => ({
        name: descById.get(Number(c?.id)) ?? null,
        count: Number(c?.count) || 0,
      }))
      .filter((s: any) => s.name && s.count > 0);

    const visitorReviews = (Array.isArray(kRev.reviews) ? kRev.reviews : [])
      .slice(0, 10)
      .map((r: any) => ({
        author: str(r?.meta?.owner?.nickname) ?? "방문자",
        rating: Number(r?.star_rating) || 5,
        contents: str(r?.contents),
        date: str(r?.registered_at)?.slice(0, 10) ?? null,
        photos: (Array.isArray(r?.photos) ? r.photos : [])
          .slice(0, 4)
          .map((p: any) => kakaoThumb(p?.url))
          .filter(Boolean),
      }))
      .filter((r: any) => r.contents);

    const blogReviews = (Array.isArray(raw.blog_review?.reviews) ? raw.blog_review.reviews : [])
      .slice(0, 8)
      .map((b: any) => ({
        title: str(b?.title) ?? "",
        contents: str(b?.contents) ?? "",
        author: str(b?.author) ?? "블로그",
        date: str(b?.registered_at)?.slice(0, 10) ?? null,
        url: str(b?.origin_url),
        photos: (Array.isArray(b?.photos) ? b.photos : [])
          .slice(0, 4)
          .map((p: any) => kakaoThumb(p?.url))
          .filter(Boolean),
      }))
      .filter((b: any) => b.title || b.contents);

    return new Response(
      JSON.stringify({
        aiTitle,
        aiSummary,
        aiKeywords,
        priceLevel,
        openStatus,
        openHours,
        photos,
        menus,
        tags,
        strengths,
        visitorReviews,
        blogReviews,
      }),
      {
        status: 200,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "public, max-age=21600",
        },
      },
    );
  } catch {
    return json({ error: "upstream_error" }, 502);
  }
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
