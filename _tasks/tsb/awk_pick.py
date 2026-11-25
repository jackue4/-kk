"""从觉醒演出的连拍里挑出漫画帧（整张近似黑白的）和它们前后各一张，拼成一条。用法：python awk_pick.py <英雄id> [标签]"""
from PIL import Image
import glob, sys
hid=sys.argv[1]; tag=sys.argv[2] if len(sys.argv)>2 else ''
fs=sorted(glob.glob('_shots/preview/tsb_%s_awk_[0-9][0-9].jpg'%hid))
bw=[]
for i,f in enumerate(fs):
    im=Image.open(f).convert('RGB').resize((64,36))
    px=list(im.get_flattened_data()) if hasattr(im,'get_flattened_data') else list(im.getdata())
    if sum(max(p)-min(p) for p in px)/len(px)<10: bw.append(i)
print(hid,'漫画帧', [fs[i][-6:-4] for i in bw])
if bw:
    # 蓄势一张 + 三种漫画帧各一张 + 放开一张
    idx=[max(bw[0]-3,0), bw[0], bw[len(bw)//2-0] if len(bw)>2 else bw[-1], bw[-1], min(bw[-1]+3,len(fs)-1)]
    seen=[]; [seen.append(i) for i in idx if i not in seen]
    sheet=Image.new('RGB',(480*len(seen),270))
    for k,i in enumerate(seen):
        sheet.paste(Image.open(fs[i]).resize((480,270),Image.LANCZOS),(480*k,0))
    out='_shots/preview/tsb_awk_pick_%s%s.jpg'%(hid,tag)
    sheet.save(out,quality=90); print(out)
