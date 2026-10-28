"""Builds the 1024 px App Store icon from docs/brand/iVidiBlocks_logo.jpeg.

The logo sits on a rounded card on white, with the title and the top piece
overhanging the card. The icon keeps the whole logo and fills everything
outside the card (white page, card frame, antialias) with the card navy,
so iOS can apply its own corner mask.

Usage: python3 scripts/make_icon.py docs/brand/iVidiBlocks_logo.jpeg \
           Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
src, out_path = sys.argv[1], sys.argv[2]
im=Image.open(src).convert('RGB'); W,H=im.size
navy=(12,13,33)
interior=Image.new('L',(W,H),0); ImageDraw.Draw(interior).rounded_rectangle((846,239,1905,1329), radius=170, fill=255)
r,g,b=im.split()
mx=ImageChops.lighter(ImageChops.lighter(r,g),b); mn=ImageChops.darker(ImageChops.darker(r,g),b)
satv=ImageChops.subtract(mx,mn)
sat=satv.point(lambda v:255 if v>70 else 0).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(23))
keep=ImageChops.lighter(interior,sat)
pale=ImageChops.multiply(mx.point(lambda v:255 if v>120 else 0), satv.point(lambda v:255 if v<60 else 0))
pale=ImageChops.subtract(pale, interior).filter(ImageFilter.MaxFilter(7))
keep=ImageChops.subtract(keep, pale).filter(ImageFilter.GaussianBlur(1.5))
out=Image.composite(im, Image.new('RGB',(W,H),navy), keep)
side=1300; cx,cy=(760+1992)//2,(171+1352)//2
out.crop((cx-side//2, cy-side//2, cx+side//2, cy+side//2)).resize((1024,1024),Image.LANCZOS).save(out_path)
