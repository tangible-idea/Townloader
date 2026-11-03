#!/usr/bin/env bash
# townloader.web.app 을 site/public 에 빌드합니다.
#   - site/src (메인, 404, CSS, JS, 미디어)를 그대로 복사
#   - PRIVACY.md / PRIVACY.ko.md / SUPPORT.md 를 같은 디자인의 HTML 로 변환
#   - 페이지에 쓰인 글자만 남겨 Pretendard 서브셋 (fonttools 필요: pip install fonttools brotli)
# 배포: firebase deploy --only hosting:townloader
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=site/public
URL=https://townloader.web.app
PY=${PYTHON:-python3}

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R site/src/. "$OUT/"
mkdir -p "$OUT/privacy/ko" "$OUT/support"

render() { # src dest lang title description path current
  local body
  body=$(npx -y marked@15.0.12 --gfm -i "$1" \
    | sed -e 's#href="PRIVACY.ko.md"#href="/privacy/ko"#g' \
          -e 's#href="PRIVACY.md"#href="/privacy"#g' \
          -e 's#href="SUPPORT.md"#href="/support"#g' \
          -e 's#>PRIVACY.ko.md<#>한국어로 보기<#g' \
          -e 's#>PRIVACY.md<#>Read in English<#g')
  local cur=""
  [ "$7" = support ] && cur=' aria-current="page"'
  cat > "$2" <<HTML
<!doctype html>
<html lang="$3">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>$4</title>
<meta name="description" content="$5">
<link rel="canonical" href="$URL$6">
<meta name="theme-color" content="#ffffff">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Townloader">
<meta property="og:url" content="$URL$6">
<meta property="og:title" content="$4">
<meta property="og:description" content="$5">
<meta property="og:image" content="$URL/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/site.css">
</head>
<body>
<a class="skip" href="#main">본문으로 건너뛰기</a>
<header class="bar">
  <a class="bar__brand" href="/" aria-label="Townloader 홈">
    <img src="/media/logo.png" alt="" width="32" height="29">
    <span>Townloader</span>
  </a>
  <nav class="bar__nav" aria-label="주요 메뉴" lang="ko">
    <a class="navlink" href="/#how"><span>작동 방식</span></a>
    <a class="navlink" href="/#features"><span>기능</span></a>
    <a class="navlink" href="/support"$cur><span>지원</span></a>
  </nav>
</header>
<main id="main" tabindex="-1" class="doc">
$body
</main>
<footer class="foot" lang="ko">
  <div class="foot__grid">
    <nav class="foot__links" aria-label="도움말과 정책">
      <a href="/support"><span>고객 지원</span></a>
      <a href="/privacy/ko"><span>개인정보처리방침</span></a>
      <a href="/privacy" lang="en"><span>Privacy Policy</span></a>
      <a href="https://github.com/tangible-idea/Tandi/issues/new"><span>문의하기</span></a>
    </nav>
    <p class="foot__fine">© 2026 Tangible Idea</p>
  </div>
</footer>
</body>
</html>
HTML
}

render PRIVACY.md    "$OUT/privacy/index.html"    en "Townloader Privacy Policy" \
  "What information Townloader handles, where it is stored, and which services receive it." /privacy privacy
render PRIVACY.ko.md "$OUT/privacy/ko/index.html" ko "Townloader 개인정보처리방침" \
  "Townloader가 다루는 정보와 저장 위치, 정보를 받는 외부 서비스, 기기 권한과 계정 삭제 방법을 안내합니다." /privacy/ko privacy
render SUPPORT.md    "$OUT/support/index.html"    ko "Townloader 고객 지원" \
  "Townloader 자주 묻는 질문과 문의 방법. 공유 목록, 저장 위치, 사진 권한, 화질 설정을 안내합니다." /support support

cat > "$OUT/robots.txt" <<TXT
User-agent: *
Allow: /
Sitemap: $URL/sitemap.xml
TXT

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
  for p in / /support /privacy/ko /privacy; do echo "  <url><loc>$URL$p</loc></url>"; done
  echo '</urlset>'
} > "$OUT/sitemap.xml"

"$PY" scripts/subset_fonts.py "$OUT"
echo "built $OUT"
