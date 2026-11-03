# townloader.web.app 디자인 노트

/awwwards 스킬(github.com/juliobsz/skills) 흐름으로 만든 메인 페이지의 기준 문서입니다.
다음에 고칠 때 이 문서를 먼저 읽고 맞춥니다.

## Brief

- 대상: 인스타그램·Threads로 여행지, 맛집, 데이트 코스를 찾는 한국어 사용자
- 할 일: 앱이 무엇을 하는지 3초 안에 알리고, 홍보 영상(39.8초, 세로)을 보여 주고, 지원과 개인정보 페이지로 보낸다
- 자산: 홍보 영상 `townloader-promo-v3.mp4`, 앱 로고, 스토어 스크린샷 5장(샘플 계정 @marks.photo, 제주 데이터)
- 가정: App Store 링크가 아직 없어 CTA는 "출시 준비 중"으로 둔다 (`placeholder`)
- 스택: 이 저장소의 기존 방식(정적 HTML + `scripts/build_site.sh` + Firebase Hosting). 프레임워크 없이 GSAP, ScrollTrigger, Lenis만 `site/src/vendor`에 둔다

## Concept

세 후보 (독창성 / 적합 / 구현 / 이식성, 이식성은 낮을수록 좋음)

| | 아이디어 | 앵커 | 점수 |
|---|---|---|---|
| A. 제품의 재료 | 글이 지도가 된다: 캡션 속 장소 이름이 하나씩 형광펜으로 찾혀 제주 지도 위 핀으로 꽂히고, 핀을 잇는 코스가 그려진다 | 앱이 실제로 캡션과 사진 속 글자에서 장소를 찾는다. 샘플 데이터가 제주 | 4 / 5 / 4 / 1 |
| B. 이름 | Town + loader: 페이지 전체가 다운로드 진행 막대 | 앱 이름 | 2 / 3 / 5 / 4 |
| C. 영상의 이야기 | 페이지가 커플 대화방: 말풍선이 섹션을 연다 | 홍보 영상 서사 | 3 / 3 / 4 / 3 |

A를 고른다. 앱이 하는 일 그 자체라 다른 브랜드로 옮길 수 없다. C에서 마지막 문구("데이트 코스 짜다 싸우지 말고")만 가져와 맺음 섹션에 쓴다.

```
Idea:        인스타 글 한 편이 스크롤하는 동안 지도 한 장이 된다
Metaphor:    지도에 핀을 꽂고 형광펜으로 줄을 긋는 여행 준비
Signature:   스티키 스테이지. 스크롤 진행도 하나가 캡션 하이라이트, 핀, 코스 선, 장소 개수를 함께 움직인다 (patterns.md 1, 2)
Emotion:     "아, 이거 내가 매번 손으로 하던 거네"
Motion verb: 핀처럼 꽂힌다 (위에서 떨어져 살짝 튕기고 멈춤)
Screenshot:  캡션 6곳이 칠해지고 제주 지도에 핀 6개와 점선 코스가 이어진 장면
```

## System

- Palette
  - ground `#ffffff` (앱 바탕)
  - ink `#1b1b1f`
  - muted `#5c5f66` (흰 바탕 AA 6.3:1)
  - line `#e4e6ea`
  - sea `#eaf0f5` (지도 바다, 영상의 채팅 바닥 #eef1f4 에서 옮김)
  - accent `#e8590c` (앱의 "장소 80곳" 테두리 주황. 핀, 형광펜, 포커스 링에만). 작은 글자에는 `#c2410c`(AA 5.2:1)
  - 로고 그라데이션은 로고에만 쓰고 다른 곳에는 번지지 않는다
- Type: Pretendard 하나 (Regular 400, SemiBold 600, ExtraBold 800). 디스플레이는 ExtraBold, 자간 -0.045em, 행간 1.02. 본문 17px/1.6. 숫자는 tabular
  - 빌드 때 페이지에 쓰인 글자만 남겨 서브셋한다 (`scripts/subset_fonts.py`)
- Grid: 12열, 여백 = gutter `clamp(20px, 4.2vw, 64px)`. 세로 기준선 1열, 7열 두 개에 모든 블록을 건다
- Shape: 미디어와 카드 반경 `22px` 하나, 버튼은 pill
- Motion: ease `expo.out` 계열 하나(`cubic-bezier(.16,1,.3,1)`), 핀만 `back.out(1.6)`. 큰 것 0.9s, 작은 것 0.35s, 스태거 40ms
- 섹션 구성 (패밀리 중복 없음)
  1. Hero: split frame. 왼쪽 7열 디스플레이 문장, 오른쪽에 영상(9:16)
  2. How: sticky narrative. 왼쪽 캡션 카드, 오른쪽 제주 지도
  3. Features: index list. 행 위에 포인터를 두면 실제 앱 화면이 따라온다. 폰에서는 행 안의 썸네일
  4. Statement: 한 문장을 크게
  5. Footer finale: 큰 워드마크와 실제 링크
- Idle: 마지막으로 꽂힌 핀에서 물결 링이 천천히 퍼지고, 영상은 계속 재생된다. 줄인 모션에서는 둘 다 멈춘다

## Genericness test

- 처음 떠올린 히어로는 "가운데 정렬 제목 + 폰 목업"이었다. 흔하고, 영상 쪽에서 금지한 "빈 캔버스 위 작은 폰"과도 겹친다. split frame으로 바꾸고 영상을 크게 둔다
- 기능 소개를 카드 3장으로 두지 않고, 실제 앱 화면이 따라오는 index list로 둔다
- 섹션마다 eyebrow 라벨을 달지 않는다

## 샘플 콘텐츠

- How 섹션의 캡션은 설명용으로 쓴 예시 글이다. 계정명은 스토어 스크린샷의 샘플 계정 @marks.photo 를 쓴다. 장소는 실제 제주 지명, 지도 위치는 대략적인 그림이다
