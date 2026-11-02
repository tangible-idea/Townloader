#!/usr/bin/env python3
"""지도 장소 카드의 말풍선 나인패치(assets/map/bubble.png)를 만든다.

그림자 + 둥근 몸통 + 가운데 꼬리를 3배율로 그린다. 늘이는 구간은
lib/ui/map/place_card_image.dart 의 _Bubble 상수와 맞아야 한다:

  가로: 꼬리 양옆 [18, 30], [52, 64] (같은 길이라 늘려도 꼬리가 가운데에 남는다)
  세로: [18, 40]
  내용: 몸통 안쪽 6 (x 11..71, y 11..47)

값은 모두 논리 픽셀(1배율)이다. 모양을 바꾸면 위 숫자도 함께 고친다.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCALE = 3  # 저장 배율
SS = 4  # 가장자리를 매끄럽게 하려고 크게 그린 뒤 줄이는 배수

PAD = 5  # 그림자 자리(좌·우·위)
PAD_BOTTOM = 3
BODY_W, BODY_H = 72, 48
RADIUS = 12
TAIL_HALF, TAIL_H = 9, 9

W = BODY_W + PAD * 2
H = PAD + BODY_H + TAIL_H + PAD_BOTTOM


def shape(k: float) -> Image.Image:
    """흰 말풍선 모양 마스크. k 는 1 논리 픽셀의 크기."""
    mask = Image.new("L", (round(W * k), round(H * k)), 0)
    draw = ImageDraw.Draw(mask)
    left, top = PAD * k, PAD * k
    right, bottom = (PAD + BODY_W) * k, (PAD + BODY_H) * k
    draw.rounded_rectangle([left, top, right, bottom], radius=RADIUS * k, fill=255)
    cx = W / 2 * k
    draw.polygon(
        [(cx - TAIL_HALF * k, bottom - k), (cx, bottom + TAIL_H * k), (cx + TAIL_HALF * k, bottom - k)],
        fill=255,
    )
    return mask


def main() -> None:
    k = SCALE * SS
    mask = shape(k)
    size = mask.size

    # 그림자: 모양을 1px 아래로 내려 흐리게.
    shadow_mask = Image.new("L", size, 0)
    shadow_mask.paste(mask, (0, round(1 * k)))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(2.2 * k))
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow.putalpha(shadow_mask.point(lambda a: a * 0x50 // 255))

    body = Image.new("RGBA", size, (255, 255, 255, 0))
    body.putalpha(mask)

    out = Image.alpha_composite(shadow, body)
    out = out.resize((W * SCALE, H * SCALE), Image.LANCZOS)
    path = Path(__file__).resolve().parent.parent / "assets/map/bubble.png"
    out.save(path)
    print(f"{path} {out.size}")


if __name__ == "__main__":
    main()
