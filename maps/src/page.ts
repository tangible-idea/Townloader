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
<div id="sheet-backdrop" class="sheet-backdrop" hidden>
  <div id="place-sheet" class="place-sheet" role="dialog" aria-modal="true"></div>
</div>
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
  marker.on("click", () => selectPlace(index, true));
  return marker;
});

function placeSubtitle(place) {
  const parts = [];
  if (place.category) parts.push(place.category);
  if (place.rating && place.rating > 0) parts.push("★ " + Number(place.rating).toFixed(1));
  if (parts.length) return parts.join(" · ");
  if (place.address) return place.address;
  return nameOf(MAP.posts[place.post]);
}

// 앱처럼 자리가 나는 주요 장소들 위에 말풍선 카드를 미리 띄운다(겹치면 숨기고 확대할수록 더 보인다).
let selectedPlace = -1;
const BUBBLE_W = 132;
const BUBBLE_H = 128;

const bubbles = MAP.places.map((place, index) => {
  const wrap = el("div", "bcard");
  wrap.style.setProperty("--item", colorOf(place.post));
  const ph = el("div", "bcard-photo");
  if (place.photo) {
    const img = document.createElement("img");
    img.src = place.photo;
    img.loading = "lazy";
    img.referrerPolicy = "no-referrer";
    img.alt = "";
    img.setAttribute("onerror", "this.remove()");
    ph.append(img);
  }
  wrap.append(ph);
  const info = el("div", "bcard-info");
  info.append(el("strong", "bcard-title", place.name));
  info.append(el("span", "bcard-sub", placeSubtitle(place)));
  wrap.append(info);
  const icon = L.divIcon({
    className: "bcard-icon",
    html: wrap.outerHTML,
    iconSize: [BUBBLE_W, BUBBLE_H],
    iconAnchor: [BUBBLE_W / 2, BUBBLE_H + 5],
  });
  const bm = L.marker([place.lat, place.lng], { icon, zIndexOffset: 500 - index });
  bm.on("click", () => selectPlace(index, true));
  return bm;
});

function updateBubbles() {
  const size = map.getSize();
  const order = MAP.places.map((_, i) => i).sort((a, b) => {
    if (a === selectedPlace) return -1;
    if (b === selectedPlace) return 1;
    const pa = MAP.places[a], pb = MAP.places[b];
    const sa = (pa.photo ? 2 : 0) + (pa.rating ? 1 : 0);
    const sb = (pb.photo ? 2 : 0) + (pb.rating ? 1 : 0);
    return sb - sa || a - b;
  });
  const boxes = [];
  for (const i of order) {
    const place = MAP.places[i];
    const pt = map.latLngToContainerPoint([place.lat, place.lng]);
    const box = {
      l: pt.x - BUBBLE_W / 2 - 4,
      r: pt.x + BUBBLE_W / 2 + 4,
      t: pt.y - BUBBLE_H - 10,
      b: pt.y + 4,
    };
    const inView = box.r > 8 && box.l < size.x - 8 && box.b > 8 && box.t < size.y - 8;
    const overlaps = boxes.some(
      (o) => !(box.r < o.l || box.l > o.r || box.b < o.t || box.t > o.b),
    );
    if (i === selectedPlace || (inView && !overlaps)) {
      boxes.push(box);
      if (!map.hasLayer(bubbles[i])) bubbles[i].addTo(map);
      const node = bubbles[i].getElement();
      if (node) node.classList.toggle("is-selected", i === selectedPlace);
    } else if (map.hasLayer(bubbles[i])) {
      map.removeLayer(bubbles[i]);
    }
  }
}

map.on("moveend zoomend", updateBubbles);

if (markers.length) {
  map.fitBounds(L.featureGroup(markers).getBounds(), { padding: [54, 44], maxZoom: 15 });
} else {
  map.setView([37.5665, 126.978], 11);
}
setTimeout(updateBubbles, 60);

function selectPlace(index, openDetail) {
  selectedPlace = index;
  updateBubbles();
  if (openDetail) showPlaceSheet(index);
}

function flyTo(index) {
  const place = MAP.places[index];
  selectedPlace = index;
  document.getElementById("map").scrollIntoView({ behavior: "smooth", block: "center" });
  map.flyTo([place.lat, place.lng], Math.max(map.getZoom(), 15), { duration: 0.8 });
  setTimeout(() => {
    updateBubbles();
    showPlaceSheet(index);
  }, 450);
}

function focusPost(index) {
  closeSheet();
  const card = document.getElementById("post-" + index);
  if (!card) return;
  card.scrollIntoView({ behavior: "smooth", block: "center" });
  card.classList.remove("flash");
  void card.offsetWidth;
  card.classList.add("flash");
}

// ── 카카오맵 장소 상세 시트 ──
const detailCache = {};
const backdrop = document.getElementById("sheet-backdrop");
const sheet = document.getElementById("place-sheet");
backdrop.addEventListener("click", (e) => {
  if (e.target === backdrop) closeSheet();
});

function closeSheet() {
  backdrop.hidden = true;
}

function formatWon(price) {
  if (price == null) return "";
  if (price <= 0) return t("무료", "Free");
  const s = Number(price).toLocaleString();
  return ko ? s + "원" : "₩" + s;
}

async function showPlaceSheet(index) {
  const place = MAP.places[index];
  if (!place) return;
  backdrop.hidden = false;
  sheet.innerHTML = "";

  const head = el("div", "sh-head");
  const titleWrap = el("div", "sh-title-wrap");
  const h3 = el("h3", "sh-title", place.name);
  titleWrap.append(h3);
  if (place.category) titleWrap.append(el("span", "muted", place.category));
  head.append(titleWrap);
  const closeBtn = el("button", "sh-close", "✕");
  closeBtn.onclick = closeSheet;
  head.append(closeBtn);
  sheet.append(head);

  const metaRow = el("div", "sh-meta");
  if (place.rating && place.rating > 0) {
    metaRow.append(el("span", "sh-rating", "★ " + Number(place.rating).toFixed(1)));
  }
  if (place.reviewCount && place.reviewCount > 0) {
    metaRow.append(
      el("span", "muted", ko ? "후기 " + place.reviewCount + "개" : place.reviewCount + " reviews"),
    );
  }
  sheet.append(metaRow);

  const addrParts = [place.address, place.phone].filter(Boolean);
  if (addrParts.length) {
    sheet.append(el("p", "sh-addr muted", addrParts.join(" · ")));
  }

  const actions = el("div", "sh-actions");
  if (place.placeUrl) {
    const kLink = el("a", "sh-btn primary", t("카카오맵에서 보기", "Open in KakaoMap"));
    kLink.href = place.placeUrl;
    kLink.target = "_blank";
    kLink.rel = "noopener";
    actions.append(kLink);
  }
  const pBtn = el("button", "sh-btn", t("게시물 보기", "View post"));
  pBtn.onclick = () => focusPost(place.post);
  actions.append(pBtn);
  sheet.append(actions);

  const body = el("div", "sh-body");
  if (place.photo) {
    const strip = el("div", "sh-photos");
    strip.append(photo(place.photo, "sh-photo"));
    body.append(strip);
  }
  if (place.summary) {
    const aiBox = el("div", "sh-ai");
    aiBox.append(el("strong", null, "✦ " + place.summary));
    body.append(aiBox);
  }
  sheet.append(body);

  if (!place.kakaoId) return;
  const loading = el("p", "muted", t("카카오맵 상세·리뷰 불러오는 중…", "Loading KakaoMap details & reviews…"));
  body.append(loading);

  try {
    if (!detailCache[place.kakaoId]) {
      const res = await fetch("/api/place/" + encodeURIComponent(place.kakaoId));
      detailCache[place.kakaoId] = res.ok ? await res.json() : null;
    }
    const d = detailCache[place.kakaoId];
    loading.remove();
    if (!d) return;
    body.innerHTML = "";

    const photos = [...(d.photos || [])];
    if (place.photo && !photos.includes(place.photo)) photos.unshift(place.photo);
    if (photos.length) {
      const strip = el("div", "sh-photos");
      photos.forEach((u) => strip.append(photo(u, "sh-photo")));
      body.append(strip);
    }

    if (d.openStatus) {
      metaRow.append(el("span", "sh-badge", d.openStatus));
    }

    if (d.aiTitle || d.aiSummary || (d.aiKeywords && d.aiKeywords.length)) {
      const aiBox = el("div", "sh-ai");
      aiBox.append(el("strong", null, "✦ " + (d.aiTitle || t("AI 장소 요약", "AI Summary"))));
      if (d.aiSummary) aiBox.append(el("p", null, d.aiSummary));
      if (d.aiKeywords && d.aiKeywords.length) {
        const kwWrap = el("div", "chips");
        d.aiKeywords.forEach((k) => kwWrap.append(el("span", "sh-tag", "#" + k)));
        aiBox.append(kwWrap);
      }
      body.append(aiBox);
    }

    if ((d.strengths && d.strengths.length) || (d.tags && d.tags.length)) {
      const tagWrap = el("div", "chips");
      (d.strengths || []).forEach((s) =>
        tagWrap.append(el("span", "sh-tag strong", s.name + " " + s.count)),
      );
      (d.tags || []).forEach((tg) => tagWrap.append(el("span", "sh-tag", "#" + tg)));
      body.append(tagWrap);
    }

    if (d.openHours && d.openHours.length) {
      const sec = el("div", "sh-sec");
      sec.append(el("h4", null, t("영업시간", "Hours")));
      d.openHours.forEach((line) => sec.append(el("div", "sh-line muted", line)));
      body.append(sec);
    }

    if (d.menus && d.menus.length) {
      const sec = el("div", "sh-sec");
      sec.append(el("h4", null, t("메뉴·요금", "Menu & Prices")));
      d.menus.forEach((m) => {
        const row = el("div", "sh-menu");
        const left = el("span", null, m.name + (m.description ? " (" + m.description + ")" : ""));
        const right = el("strong", null, formatWon(m.price));
        row.append(left, right);
        sec.append(row);
      });
      body.append(sec);
    }

    if (d.visitorReviews && d.visitorReviews.length) {
      const sec = el("div", "sh-sec");
      sec.append(
        el(
          "h4",
          null,
          (ko ? "방문자 후기 (" : "Visitor Reviews (") + d.visitorReviews.length + ")",
        ),
      );
      d.visitorReviews.forEach((r) => {
        const item = el("div", "sh-rev");
        const top = el("div", "sh-rev-top");
        top.append(el("span", "sh-rating", "★".repeat(Math.max(1, Math.min(5, r.rating || 5)))));
        top.append(el("strong", null, r.author));
        if (r.date) top.append(el("span", "muted", r.date));
        item.append(top);
        item.append(el("p", null, r.contents));
        if (r.photos && r.photos.length) {
          const rp = el("div", "sh-photos small");
          r.photos.forEach((u) => rp.append(photo(u, "sh-photo small")));
          item.append(rp);
        }
        sec.append(item);
      });
      body.append(sec);
    }

    if (d.blogReviews && d.blogReviews.length) {
      const sec = el("div", "sh-sec");
      sec.append(
        el("h4", null, (ko ? "블로그 리뷰 (" : "Blog Reviews (") + d.blogReviews.length + ")"),
      );
      d.blogReviews.forEach((b) => {
        const item = el(b.url ? "a" : "div", "sh-rev blog");
        if (b.url) {
          item.href = b.url;
          item.target = "_blank";
          item.rel = "noopener";
        }
        if (b.title) item.append(el("strong", null, b.title));
        if (b.contents) item.append(el("p", "muted", b.contents));
        if (b.photos && b.photos.length) {
          const bp = el("div", "sh-photos small");
          b.photos.forEach((u) => bp.append(photo(u, "sh-photo small")));
          item.append(bp);
        }
        item.append(el("span", "muted", [b.author, b.date].filter(Boolean).join(" · ")));
        sec.append(item);
      });
      body.append(sec);
    }
  } catch {
    loading.remove();
  }
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
      if (place.photo) {
        chip.append(photo(place.photo, "chip-thumb"));
      } else {
        chip.append(el("span", "pin"));
      }
      const label = [
        place.name + (place.approximate ? t(" · 대략", " · approx.") : ""),
        place.category || null,
        place.rating && place.rating > 0 ? "★ " + Number(place.rating).toFixed(1) : null,
      ]
        .filter(Boolean)
        .join(" · ");
      chip.append(el("span", null, label));
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
#map { height: min(54vh, 480px); min-height: 300px; }
.dot span { display: block; width: 16px; height: 16px; border-radius: 50%; background: var(--accent);
  border: 2.5px solid #fff; box-shadow: 0 1px 4px rgba(0, 0, 0, .35); }
.bcard-icon { background: none; border: none; display: flex !important; flex-direction: column;
  justify-content: flex-end; align-items: center; padding-bottom: 6px;
  filter: drop-shadow(0 4px 10px rgba(15, 23, 42, .2)) drop-shadow(0 1px 2px rgba(15, 23, 42, .12));
  transition: filter .15s ease, transform .15s ease; }
.bcard { position: relative; width: 132px; background: #fff; color: #1b1b1f; border-radius: 14px; padding: 6px 6px 7px;
  cursor: pointer; display: flex; flex-direction: column; gap: 4px; z-index: 1; }
.bcard::after { content: ""; position: absolute; left: 50%; bottom: -5px; width: 12px; height: 12px;
  background: #fff; border-radius: 0 0 3px 0; transform: translateX(-50%) rotate(45deg); z-index: -1; }
.bcard-icon.is-selected { transform: translateY(-2px);
  filter: drop-shadow(0 0 0 var(--item, var(--accent))) drop-shadow(0 6px 16px rgba(15, 23, 42, .28)); }
.bcard-icon.is-selected .bcard,
.bcard-icon.is-selected .bcard::after { background: var(--item, var(--accent)); color: #fff; }
.bcard-icon.is-selected .bcard-sub { color: rgba(255, 255, 255, .86); }
.bcard-photo { width: 100%; height: 76px; border-radius: 9px; flex: none; background: #e8eef0; overflow: hidden; }
.bcard-photo img { width: 100%; height: 100%; object-fit: cover; display: block; }
.bcard-info { display: flex; flex-direction: column; min-width: 0; padding: 1px 3px 0; }
.bcard-title { font-size: 13px; font-weight: 700; line-height: 1.25; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.bcard-sub { font-size: 11px; font-weight: 600; color: #5f6368; line-height: 1.25; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.muted { color: var(--muted); font-size: 13px; }
.chip-thumb { width: 20px; height: 20px; border-radius: 50%; flex: none; }

.sheet-backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, .45); z-index: 2000; display: flex;
  align-items: flex-end; justify-content: center; padding: 0; }
.sheet-backdrop[hidden] { display: none !important; }
@media (min-width: 680px) { .sheet-backdrop { align-items: center; padding: 24px; } }
.place-sheet { background: var(--card); color: var(--fg); width: 100%; max-width: 560px; max-height: 84vh;
  border-radius: 24px 24px 0 0; padding: 20px 20px max(24px, env(safe-area-inset-bottom)); overflow-y: auto;
  box-shadow: 0 -4px 32px rgba(0, 0, 0, .25); display: flex; flex-direction: column; gap: 10px; }
@media (min-width: 680px) { .place-sheet { border-radius: 24px; } }
.sh-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }
.sh-title-wrap { display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
.sh-title { margin: 0; font-size: 22px; font-weight: 800; line-height: 1.2; }
.sh-close { all: unset; cursor: pointer; width: 32px; height: 32px; border-radius: 50%; background: var(--chip);
  display: grid; place-items: center; font-size: 14px; flex: none; }
.sh-meta { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.sh-rating { color: var(--accent); font-weight: 800; font-size: 14px; }
.sh-badge { background: var(--chip); padding: 3px 9px; border-radius: 999px; font-size: 12px; font-weight: 600; }
.sh-addr { margin: 0; }
.sh-actions { display: flex; gap: 8px; flex-wrap: wrap; }
.sh-btn { all: unset; cursor: pointer; padding: 8px 14px; border-radius: 999px; background: var(--chip);
  font-size: 13px; font-weight: 700; text-decoration: none; }
.sh-btn.primary { background: var(--btn); color: var(--btn-fg); }
.sh-body { display: flex; flex-direction: column; gap: 14px; margin-top: 4px; }
.sh-photos { display: flex; gap: 8px; overflow-x: auto; scrollbar-width: none; }
.sh-photos::-webkit-scrollbar { display: none; }
.sh-photo { width: 148px; height: 116px; border-radius: 12px; flex: none; }
.sh-photo.small { width: 68px; height: 68px; border-radius: 8px; }
.sh-ai { background: var(--chip); padding: 12px 14px; border-radius: 14px; display: flex; flex-direction: column; gap: 6px; }
.sh-ai p { margin: 0; font-size: 14px; }
.sh-tag { background: var(--chip); padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }
.sh-tag.strong { background: color-mix(in srgb, var(--accent) 16%, var(--chip)); color: var(--accent); font-weight: 700; }
.sh-sec { display: flex; flex-direction: column; gap: 6px; }
.sh-sec h4 { margin: 0; font-size: 15px; font-weight: 800; }
.sh-line { font-size: 13px; }
.sh-menu { display: flex; justify-content: space-between; gap: 12px; font-size: 14px; padding: 3px 0; border-bottom: 1px solid var(--line); }
.sh-rev { background: var(--chip); border-radius: 14px; padding: 12px; display: flex; flex-direction: column; gap: 6px; text-decoration: none; color: inherit; }
.sh-rev p { margin: 0; font-size: 14px; white-space: pre-line; }
.sh-rev-top { display: flex; align-items: center; gap: 6px; font-size: 13px; }

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
