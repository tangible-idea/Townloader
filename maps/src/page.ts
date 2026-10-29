import type { PublicMap } from "./index";

/**
 * 앱이 없는 사람에게 보여 줄 공개 지도. 앱이 있으면 이 주소를 앱이 가로채 직접 연다.
 *
 * 앱의 Links 탭처럼 글을 카드로 늘어놓고, 위에는 지도를 둔다. 장소 칩을 누르면 지도가
 * 그 장소로 날아가고, 지도의 점을 누르면 그 장소가 나온 글 카드로 내려간다.
 */

interface Stores {
  appStore: string;
  playStore: string;
}

export function renderMapPage(
  map: PublicMap,
  pageUrl: string,
  stores: Stores,
  mapboxToken: string,
): string {
  const title = `${map.category} · Townloader`;
  const cover = map.posts.find((post) => post.coverUrl)?.coverUrl ?? null;
  return layout({
    title,
    description: `${map.places.length} places · ${map.posts.length} posts`,
    pageUrl,
    image: cover,
    body: `
<main>
  <header class="top">
    <div class="brand">Townloader</div>
    <h1>${escapeHtml(map.category)}</h1>
    <p class="meta" id="meta"></p>
    <a class="cta" id="get-app" href="${escapeHtml(stores.appStore)}">
      <span data-ko="앱에서 열기" data-en="Open in the app"></span>
    </a>
  </header>
  <section class="map-wrap"><div id="map"></div></section>
  <section id="posts" class="posts"></section>
  <footer class="foot">
    <span data-ko="게시물은 인스타그램에 있습니다. 해시태그는 숨겼어요." data-en="Posts live on Instagram. Hashtags are hidden."></span>
  </footer>
</main>
<script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
<script>
const MAP = ${scriptJson(map)};
const STORES = ${scriptJson(stores)};
const MAPBOX_TOKEN = ${scriptJson(mapboxToken)};
// 앱의 PlacesMapScreen.itemColors 와 같은 순서. 글마다 돌려 쓴다.
const COLORS = ["#0B7A5E", "#E8590C", "#1C7ED6", "#D6336C", "#7048E8", "#F08C00", "#0C8599", "#5C3B1E"];
const colorOf = (post) => COLORS[post % COLORS.length];
const nameOf = (post) => post.title || (post.author ? "@" + post.author : t("게시물", "Post"));
const ko = (navigator.language || "").toLowerCase().startsWith("ko");
const t = (k, e) => (ko ? k : e);
document.documentElement.lang = ko ? "ko" : "en";
for (const el of document.querySelectorAll("[data-ko]")) el.textContent = ko ? el.dataset.ko : el.dataset.en;
document.getElementById("meta").textContent = ko
  ? "장소 " + MAP.places.length + "곳 · 게시물 " + MAP.posts.length + "개"
  : MAP.places.length + " places · " + MAP.posts.length + " posts";
if (/android/i.test(navigator.userAgent)) document.getElementById("get-app").href = STORES.playStore;

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

/** 인스타그램 사진 주소는 만료되므로, 못 불러오면 빈 칸으로 둔다. */
function photo(url, className) {
  const box = el("div", "photo " + (className || ""));
  if (!url) return box;
  const img = new Image();
  img.loading = "lazy";
  img.decoding = "async";
  img.referrerPolicy = "no-referrer";
  img.alt = "";
  img.onload = () => box.classList.add("loaded");
  img.onerror = () => img.remove();
  img.src = url;
  box.append(img);
  return box;
}

// ── 지도 ──
const map = L.map("map", { scrollWheelZoom: false, zoomControl: false, attributionControl: true });
L.control.zoom({ position: "bottomright" }).addTo(map);
// 앱과 같은 Mapbox Outdoors 스타일. 토큰이 없으면 OpenStreetMap 기본 타일.
if (MAPBOX_TOKEN) {
  L.tileLayer("https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/512/{z}/{x}/{y}@2x?access_token=" + MAPBOX_TOKEN, {
    tileSize: 512,
    zoomOffset: -1,
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.mapbox.com/about/maps/">Mapbox</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
} else {
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
}

const markers = MAP.places.map((place, index) => {
  const icon = L.divIcon({
    className: "dot",
    html: '<span style="background:' + colorOf(place.post) + '"></span>',
    iconSize: [18, 18],
    iconAnchor: [9, 9],
  });
  const marker = L.marker([place.lat, place.lng], { icon, title: place.name }).addTo(map);
  const popup = el("div", "pop");
  popup.append(photo(place.photo, "pop-photo"));
  const text = el("div", "pop-text");
  text.append(el("strong", null, place.name));
  text.append(el("span", "muted", nameOf(MAP.posts[place.post])));
  if (place.address) text.append(el("span", "muted", place.address));
  const go = el("button", "pop-link", t("게시물 보기", "View post"));
  go.onclick = () => focusPost(place.post);
  text.append(go);
  popup.append(text);
  marker.bindPopup(popup, { closeButton: false, maxWidth: 260, minWidth: 220 });
  return marker;
});
if (markers.length) {
  map.fitBounds(L.featureGroup(markers).getBounds(), { padding: [36, 36], maxZoom: 15 });
} else {
  map.setView([37.5665, 126.978], 11);
}

function flyTo(index) {
  const place = MAP.places[index];
  document.getElementById("map").scrollIntoView({ behavior: "smooth", block: "center" });
  map.flyTo([place.lat, place.lng], Math.max(map.getZoom(), 15), { duration: 0.8 });
  setTimeout(() => markers[index].openPopup(), 850);
}

function focusPost(index) {
  const card = document.getElementById("post-" + index);
  if (!card) return;
  card.scrollIntoView({ behavior: "smooth", block: "center" });
  card.classList.remove("flash");
  void card.offsetWidth;
  card.classList.add("flash");
}

// ── 글 카드 ──
const list = document.getElementById("posts");
if (!MAP.posts.length) list.append(el("p", "empty", t("아직 저장한 글이 없어요.", "No posts yet.")));
MAP.posts.forEach((post, index) => {
  const card = el("article", "card");
  card.id = "post-" + index;
  card.style.setProperty("--item", colorOf(index));

  const images = post.imageUrls.length ? post.imageUrls : post.coverUrl ? [post.coverUrl] : [];
  const gallery = el("div", "gallery");
  const strip = el("div", "strip");
  (images.length ? images : [null]).forEach((url) => strip.append(photo(url)));
  gallery.append(strip);
  if (images.length > 1) {
    const count = el("span", "count", "1 / " + images.length);
    strip.addEventListener("scroll", () => {
      const page = Math.round(strip.scrollLeft / strip.clientWidth) + 1;
      count.textContent = page + " / " + images.length;
    }, { passive: true });
    gallery.append(count);
  }
  card.append(gallery);

  const body = el("div", "body");
  if (post.title) {
    const heading = el("h2", "title");
    heading.append(el("span", "swatch"));
    heading.append(el("span", null, post.title));
    body.append(heading);
  }
  if (post.author) {
    const author = el("div", "author");
    author.append(el("span", "avatar", post.author.slice(0, 1).toUpperCase()));
    author.append(el("span", null, "@" + post.author));
    body.append(author);
  }
  if (post.caption) {
    const caption = el("p", "caption", post.caption);
    body.append(caption);
    requestAnimationFrame(() => {
      if (caption.scrollHeight > caption.clientHeight + 2) {
        const more = el("button", "more", t("더 보기", "More"));
        more.onclick = () => { caption.classList.add("open"); more.remove(); };
        caption.after(more);
      }
    });
  }
  if (post.places.length) {
    const chips = el("div", "chips");
    post.places.forEach((placeIndex) => {
      const place = MAP.places[placeIndex];
      const chip = el("button", "chip");
      chip.append(el("span", "pin"));
      chip.append(el("span", null, place.name + (place.approximate ? t(" · 대략", " · approx.") : "")));
      chip.onclick = () => flyTo(placeIndex);
      chips.append(chip);
    });
    body.append(chips);
  }
  const link = el("a", "ig", t("인스타그램에서 보기", "View on Instagram"));
  link.href = post.url;
  link.target = "_blank";
  link.rel = "noopener";
  body.append(link);
  card.append(body);
  list.append(card);
});
</script>`,
  });
}

export function renderNotFoundPage(stores: Stores): string {
  return layout({
    title: "Townloader",
    description: "",
    pageUrl: "",
    image: null,
    body: `
<main class="gone">
  <div class="brand">Townloader</div>
  <h1 data-ko="공유가 끝난 지도예요" data-en="This map is no longer shared"></h1>
  <p class="meta" data-ko="주인이 공개를 멈췄거나 주소가 잘못되었어요." data-en="The owner stopped sharing it, or the link is wrong."></p>
  <a class="cta" id="get-app" href="${escapeHtml(stores.appStore)}"><span data-ko="Townloader 받기" data-en="Get Townloader"></span></a>
</main>
<script>
const ko = (navigator.language || "").toLowerCase().startsWith("ko");
for (const el of document.querySelectorAll("[data-ko]")) el.textContent = ko ? el.dataset.ko : el.dataset.en;
if (/android/i.test(navigator.userAgent)) document.getElementById("get-app").href = ${scriptJson(stores.playStore)};
</script>`,
  });
}

function layout(options: {
  title: string;
  description: string;
  pageUrl: string;
  image: string | null;
  body: string;
}): string {
  const { title, description, pageUrl, image, body } = options;
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
${pageUrl ? `<meta property="og:url" content="${escapeHtml(pageUrl)}">` : ""}
${image ? `<meta property="og:image" content="${escapeHtml(image)}">` : ""}
<meta name="apple-itunes-app" content="app-id=6814762239">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Urbanist:wght@500;600;700;800&family=Noto+Sans+KR:wght@400;500;700&display=swap">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css">
<style>
:root {
  --bg: #f5f5f5; --card: #ffffff; --fg: #212121; --muted: #757575; --line: #eeeeee;
  --chip: #f5f5f5; --accent: #0b7a5e; --placeholder: #e0e0e0; --btn: #212121; --btn-fg: #ffffff;
  --shadow: 0 1px 2px rgba(4, 6, 15, .04), 0 8px 24px rgba(4, 6, 15, .06);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #181a20; --card: #1f222a; --fg: #fafafa; --muted: #9e9e9e; --line: #35383f;
    --chip: #35383f; --accent: #35c49a; --placeholder: #35383f; --btn: #fafafa; --btn-fg: #181a20;
    --shadow: 0 1px 2px rgba(0, 0, 0, .3);
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 15px/1.55 Urbanist, "Noto Sans KR", -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; }
main { max-width: 960px; margin: 0 auto; padding: max(20px, env(safe-area-inset-top)) 16px 40px; }
button { font: inherit; color: inherit; }

.top { display: grid; grid-template-columns: 1fr auto; grid-template-areas: "brand brand" "title cta" "meta cta"; column-gap: 12px; align-items: end; margin-bottom: 16px; }
.brand { grid-area: brand; font-weight: 800; font-size: 13px; letter-spacing: .02em; color: var(--muted); margin-bottom: 6px; }
h1 { grid-area: title; margin: 0; font-size: clamp(26px, 6vw, 36px); line-height: 1.15; font-weight: 800; letter-spacing: -.01em; word-break: keep-all; }
.meta { grid-area: meta; margin: 4px 0 0; color: var(--muted); font-size: 14px; }
.cta { grid-area: cta; align-self: center; background: var(--btn); color: var(--btn-fg); text-decoration: none; font-weight: 700;
  font-size: 14px; padding: 11px 18px; border-radius: 999px; white-space: nowrap; }

.map-wrap { border-radius: 24px; overflow: hidden; box-shadow: var(--shadow); background: var(--placeholder); margin-bottom: 20px; }
#map { height: min(48vh, 440px); min-height: 260px; }
.dot span { display: block; width: 18px; height: 18px; border-radius: 50%; background: var(--accent);
  border: 3px solid #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, .35); }
.leaflet-popup-content-wrapper { border-radius: 16px; padding: 0; overflow: hidden; background: var(--card); color: var(--fg); }
.leaflet-popup-tip { background: var(--card); }
.leaflet-popup-content { margin: 0; width: auto !important; }
.pop { display: flex; gap: 10px; padding: 8px; align-items: center; font: 14px/1.4 Urbanist, "Noto Sans KR", sans-serif; }
.pop-photo { width: 64px; height: 64px; flex: none; border-radius: 10px; }
.pop-text { display: flex; flex-direction: column; min-width: 0; gap: 2px; }
.pop-text strong { font-weight: 700; }
.pop-link { all: unset; cursor: pointer; font-weight: 700; color: var(--accent); margin-top: 2px; }
.muted { color: var(--muted); font-size: 13px; }

.posts { display: grid; gap: 16px; grid-template-columns: 1fr; }
@media (min-width: 720px) { .posts { grid-template-columns: 1fr 1fr; } }
.card { background: var(--card); border-radius: 20px; overflow: hidden; box-shadow: var(--shadow); display: flex; flex-direction: column; }
.card.flash { animation: flash 1.2s ease; }
@keyframes flash { 0%, 60% { box-shadow: 0 0 0 3px var(--item, var(--accent)), var(--shadow); } 100% { box-shadow: var(--shadow); } }

.gallery { position: relative; }
.strip { display: flex; overflow-x: auto; scroll-snap-type: x mandatory; scrollbar-width: none; }
.strip::-webkit-scrollbar { display: none; }
.strip .photo { flex: 0 0 100%; aspect-ratio: 4 / 5; scroll-snap-align: start; }
.photo { position: relative; background: var(--placeholder); overflow: hidden; }
.photo img { width: 100%; height: 100%; object-fit: cover; display: block; opacity: 0; transition: opacity .25s; }
.photo.loaded img { opacity: 1; }
.count { position: absolute; top: 12px; right: 12px; background: rgba(0, 0, 0, .55); color: #fff;
  font-size: 12px; font-weight: 700; padding: 3px 9px; border-radius: 999px; }

.body { padding: 14px 16px 16px; display: flex; flex-direction: column; gap: 10px; flex: 1; }
.author { display: flex; align-items: center; gap: 8px; font-weight: 600; color: var(--muted); font-size: 14px; }
.avatar { width: 28px; height: 28px; border-radius: 50%; background: var(--chip); display: grid; place-items: center; font-size: 13px; font-weight: 800; }
.caption { margin: 0; white-space: pre-line; overflow-wrap: anywhere; display: -webkit-box; -webkit-line-clamp: 4; -webkit-box-orient: vertical; overflow: hidden; }
.caption.open { display: block; }
.more { all: unset; cursor: pointer; color: var(--muted); font-weight: 600; font-size: 14px; margin-top: -6px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { all: unset; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; background: var(--chip);
  border-radius: 999px; padding: 6px 12px 6px 10px; font-size: 13px; font-weight: 600; max-width: 100%; }
.chip span:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pin { width: 8px; height: 8px; border-radius: 50%; background: var(--item, var(--accent)); flex: none; }
.title { margin: 0; display: flex; align-items: center; gap: 8px; font-size: 18px; line-height: 1.3; font-weight: 800; word-break: keep-all; }
.swatch { width: 12px; height: 12px; border-radius: 50%; background: var(--item); flex: none; box-shadow: 0 0 0 3px color-mix(in srgb, var(--item) 22%, transparent); }
.ig { margin-top: auto; align-self: flex-start; color: var(--muted); font-size: 13px; font-weight: 600; text-decoration: none; }
.ig::after { content: " ↗"; }
.empty { color: var(--muted); text-align: center; padding: 24px; }
.foot { color: var(--muted); font-size: 12px; text-align: center; padding-top: 28px; }
.gone { text-align: center; padding-top: 18vh; }
.gone .cta { display: inline-block; margin-top: 20px; }
</style>
</head>
<body>
${body}
</body>
</html>`;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);
}

/** `<script>` 안에 넣어도 태그가 닫히지 않게 `<` 를 바꾼다. */
function scriptJson(value: unknown): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}
