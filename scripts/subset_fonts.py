#!/usr/bin/env python3
"""site/public 의 HTML·JS에 쓰인 글자만 남겨 Pretendard 를 서브셋한다.

필요: pip install fonttools brotli
사용: python3 scripts/subset_fonts.py site/public
"""
import html
import pathlib
import re
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "fonts-src"
WEIGHTS = {"400": "Pretendard-Regular.woff2", "600": "Pretendard-SemiBold.woff2", "800": "Pretendard-ExtraBold.woff2"}


def collect(public: pathlib.Path) -> str:
    chars = set(chr(c) for c in range(0x20, 0x7F))  # ASCII 전부
    chars.update("“”‘’…·©×→")
    for path in list(public.rglob("*.html")) + list(public.rglob("*.js")):
        if "vendor" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"<script[^>]*type=\"application/ld\+json\"[^>]*>.*?</script>", " ", text, flags=re.S)
        chars.update(html.unescape(text))
    return "".join(sorted(c for c in chars if c.isprintable()))


def main() -> None:
    public = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "site/public")
    out = public / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    text = collect(public)
    for weight, name in WEIGHTS.items():
        opts = subset.Options()
        opts.flavor = "woff2"
        opts.layout_features = ["kern", "liga", "tnum", "calt"]
        opts.name_IDs = ["*"]
        font = subset.load_font(str(SRC / name), opts)
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        dest = out / f"pretendard-{weight}.woff2"
        subset.save_font(font, str(dest), opts)
        print(f"{dest.relative_to(public)}: {dest.stat().st_size // 1024} KB")
    print(f"{len(text)} glyphs")


if __name__ == "__main__":
    main()
