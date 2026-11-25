"""把觉醒演出的连拍（_shots/preview/tsb_<英雄>_awk_NN.jpg）拼成总览图。用法：python awk_sheet.py <英雄id> [起 止 每格宽]"""
from PIL import Image, ImageDraw
import glob, os, sys
hid=sys.argv[1]
a=int(sys.argv[2]) if len(sys.argv)>2 else 0
b=int(sys.argv[3]) if len(sys.argv)>3 else 29
w=int(sys.argv[4]) if len(sys.argv)>4 else 320
h=w*9//16
fs=[f for f in sorted(glob.glob('_shots/preview/tsb_%s_awk_[0-9][0-9].jpg'%hid)) if a<=int(f[-6:-4])<=b]
cols=6 if w<=320 else 3
rows=(len(fs)+cols-1)//cols
sheet=Image.new('RGB',(cols*w, rows*h),(20,20,20))
d=ImageDraw.Draw(sheet)
for i,f in enumerate(fs):
    im=Image.open(f).resize((w,h),Image.LANCZOS)
    x=(i%cols)*w; y=(i//cols)*h
    sheet.paste(im,(x,y))
    d.rectangle((x,y,x+34,y+16),fill=(0,0,0))
    d.text((x+3,y+2),os.path.basename(f)[-6:-4],fill=(255,255,0))
out='_shots/preview/tsb_awk_sheet_%s%s.jpg'%(hid,'' if w<=320 else '_big')
sheet.save(out,quality=88)
print(len(fs), sheet.size, out)
