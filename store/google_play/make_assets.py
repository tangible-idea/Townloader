"""Play 스토어용 그래픽을 App Store 자산에서 만든다.

  python3 store/google_play/make_assets.py

- icon_512.png            512x512 (iOS 1024 아이콘 축소)
- <locale>/feature_graphic.png  1024x500
- <locale>/0N_*.png       1080x1920 (9:16). Play 는 스크린샷을 16:9/9:16 만 받으므로
                          App Store 원본(1320x2868)을 높이에 맞춰 줄이고 좌우를 가장자리 색으로 늘린다.
"""
import glob
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = 'store/google_play'
FONTS = 'test/store/fonts/'
ICON = 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png'
# Play 로케일 -> (App Store 스크린샷 폴더, 피처 그래픽 한 줄 문구)
LOCALES = {
    'ko-KR': ('ko', '링크 하나로, 원본 화질 그대로'),
    'en-US': ('en-US', 'Save public posts in original quality'),
}

icon = Image.open(ICON).convert('RGBA')
icon.resize((512, 512), Image.LANCZOS).save(f'{ROOT}/icon_512.png')
bg = icon.getpixel((10, 10))[:3]

for loc, (src, line) in LOCALES.items():
    os.makedirs(f'{ROOT}/{loc}', exist_ok=True)

    fg = Image.new('RGB', (1024, 500), bg)
    d = ImageDraw.Draw(fg)
    ic = icon.resize((300, 300), Image.LANCZOS)
    fg.paste(ic, (70, 100), ic)
    d.text((410, 170), 'Townloader', font=ImageFont.truetype(FONTS + 'Pretendard-ExtraBold.otf', 72), fill=(26, 26, 26))
    d.text((412, 270), line, font=ImageFont.truetype(FONTS + 'Pretendard-Medium.otf', 34), fill=(90, 90, 90))
    fg.save(f'{ROOT}/{loc}/feature_graphic.png')

    for p in sorted(glob.glob(f'store/app_store/screenshots/{src}/*.png')):
        im = Image.open(p).convert('RGB')
        W, H = 1080, 1920
        w = round(im.width * H / im.height)
        im = im.resize((w, H), Image.LANCZOS)
        c = Image.new('RGB', (W, H))
        off = (W - w) // 2
        c.paste(im.crop((0, 0, 1, H)).resize((off, H)), (0, 0))
        c.paste(im.crop((w - 1, 0, w, H)).resize((W - w - off, H)), (off + w, 0))
        c.paste(im, (off, 0))
        c.save(f'{ROOT}/{loc}/' + os.path.basename(p))
