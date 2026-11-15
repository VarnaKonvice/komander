#!/usr/bin/env python3
"""Lázeňský Commander: re-edit approved V5 without generating any new media.
Keeps exact V5 visual track except 14–18 seconds; keeps audio packet stream unchanged.
Burns brief non-duplicated Czech subtitles and a 0-second silent-viewing hook.
"""
from pathlib import Path
import subprocess, json, os, sys, hashlib, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import imageio_ffmpeg

ROOT=Path(os.environ.get("BOHANES_PROJECT_DIR","~/Documents/Bohanes Technologies")).expanduser()
V5=ROOT/"video-marketing/short-v5/Commander-Short-V5-master.mp4"
SCREEN=ROOT/"web-site-sync/docs/bohanes-technologies/web/site/screens/commander-today.png"
OUT=ROOT/"video-marketing/short-v6"
OUT.mkdir(parents=True,exist_ok=True)
PNG=OUT/"scene-iphone-approved-dnes.png"
HOOKS=[OUT/"hook-klid.png",OUT/"hook-rozpis.png"]
SUB=OUT/"titulky-cs.ass"
MASTER=OUT/"Commander-Short-V6-iPhone-titulky-master.mp4"
WEB=OUT/"Commander-Short-V6-web.mp4"
F=imageio_ffmpeg.get_ffmpeg_exe()
W,H=1080,1920
def ff(*args):
    cmd=[F,"-hide_banner","-nostdin","-y",*map(str,args)]
    print("RUN", " ".join(cmd)[:550],flush=True)
    subprocess.run(cmd,check=True)
def font(size,bold=False):
    src=("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf")
    if not Path(src).exists():
        src="/System/Library/Fonts/Helvetica.ttc"
    return ImageFont.truetype(src,size)
assert V5.is_file() and SCREEN.is_file(),(V5,SCREEN)
sc=Image.open(SCREEN).convert("RGB")
assert sc.size==(1179,2556),f"Unexpected iPhone screenshot shape: {sc.size}"
# 4-sec iPhone screen: photograph is an unaltered scale-to-fit copy of the approved iOS "Dnes",
# with ALL header and bottom tabs in-frame. No crop, fake controls or Android assets.
bg=Image.new("RGB",(W,H))
pix=bg.load()
for y in range(H):
    yy=y/(H-1)
    for x in range(W):
        xx=x/(W-1)
        pulse=math.exp(-((xx-.74)**2/.19+(yy-.4)**2/.12))
        pix[x,y]=(
          int(max(0,min(255,13+5*yy+9*pulse))),
          int(max(0,min(255,23+12*yy+31*pulse))),
          int(max(0,min(255,45+24*yy+41*pulse))),
        )
# soft pale blue halo that does not touch the original screenshot
halo=Image.new("RGBA",(W,H),(0,0,0,0))
hd=ImageDraw.Draw(halo)
hd.ellipse((100,200,1020,1810),fill=(35,164,179,41))
halo=halo.filter(ImageFilter.GaussianBlur(75))
bg=Image.alpha_composite(bg.convert("RGBA"),halo)
sh=1600
sw=round(sc.width*sh/sc.height)
image=sc.resize((sw,sh),Image.Resampling.LANCZOS).convert("RGBA")
x=(W-sw)//2; y=212
shade=Image.new("RGBA",(W,H),(0,0,0,0))
d=ImageDraw.Draw(shade)
d.rounded_rectangle((x-22,y-22,x+sw+22,y+sh+22),radius=37,fill=(2,12,30,170))
shade=shade.filter(ImageFilter.GaussianBlur(27))
bg=Image.alpha_composite(bg,shade)
draw=ImageDraw.Draw(bg)
draw.rounded_rectangle((x-11,y-11,x+sw+11,y+sh+11),radius=18,fill=(235,249,255,248))
bg.alpha_composite(image,(x,y))
# only small supporting label, lower than iPhone's screenshot
draw=ImageDraw.Draw(bg)
tag="SKUTEČNÁ OBRAZOVKA iPHONU"
f=font(32,True)
bb=draw.textbbox((0,0),tag,font=f)
draw.text(((W-(bb[2]-bb[0]))/2,1850),tag,font=f,fill=(154,233,231,255))
bg.convert("RGB").save(PNG,optimize=True)
print("CREATED SOURCE",PNG,sc.size,"fitted",image.size,"position",x,y)

def make_hook(text,target,accent):
    layer=Image.new("RGBA",(W,H),(0,0,0,0))
    d=ImageDraw.Draw(layer)
    # rectangular editorial label; compact radius, never pill-like
    left,top,right,bottom=55,114,1025,312
    d.rounded_rectangle((left,top,right,bottom),radius=16,fill=(10,34,57,222),
                        outline=(64,191,189,180),width=3)
    d.rectangle((left,top,left+12,bottom),fill=(24,182,170,255))
    small=font(28,True)
    d.text((left+40,top+22),"VÁŠ POMOCNÍK DO LÁZNÍ",font=small,fill=(130,223,214,255))
    f=font(62,True)
    bb=d.textbbox((0,0),text,font=f)
    if (bb[2]-bb[0])>905:
        f=font(55,True);bb=d.textbbox((0,0),text,font=f)
    d.text(((W-(bb[2]-bb[0]))/2,top+96),text,font=f,fill=accent)
    layer.save(target)
make_hook("V LÁZNÍCH MÁ BÝT KLID.",HOOKS[0],(255,255,255,255))
make_hook("NE HLEDÁNÍ V ROZPISU.",HOOKS[1],(126,240,224,255))

def stamp(s):
    hr=int(s//3600);m=int((s%3600)//60);s2=s%60
    return f"{hr}:{m:02d}:{s2:05.2f}"
# ASS: all visible words below are reused from V5 narration, condensed in 2 places.
# The outro already contains the original logo + claim, and is deliberately uncluttered.
subtitles=[
 (4.55,7.90,"Ne pořád hledat, co vás čeká.\\NA kdy máte vyrazit.","Caption"),
 (9.55,11.75,"Rozpis vyfotíte a zkontrolujete.","Caption"),
 (11.75,13.22,"A máte ho v telefonu.","Caption"),
 (14.10,16.12,"Víte, co vás čeká.","OnPhone"),
 (16.12,17.88,"Telefon vám připomene odchod.","OnPhone"),
 (19.08,21.25,"A pak už si jen užíváte svůj pobyt.","Caption"),
]
# ASS Color is &HAABBGGRR; inside the first 18s white, outlined against varied footage.
header="""[Script Info]
Title: Lázeňský Commander – V6 – schválený iPhone a titulky
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Caption,Arial,64,&H00FFFFFF,&H00FFFFFF,&HBC06132B,&H9C05132C,-1,0,0,0,100,100,0,0,1,5,2,2,85,85,154,1
Style: OnPhone,Arial,57,&H00FFFFFF,&H00FFFFFF,&HBB06132B,&H9C05132C,-1,0,0,0,100,100,0,0,1,5,2,8,65,65,65,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
with SUB.open("w",encoding="utf-8") as f:
    f.write(header)
    for st,en,t,sty in subtitles:
        f.write(f"Dialogue: 0,{stamp(st)},{stamp(en)},{sty},,0,0,0,,{{\\fad(170,130)}}{t}\n")
print("CREATED SUBTITLES",SUB,"segments",len(subtitles))
# Mac video asset as primary source; no new AI generation, no audio resynthesis.
# End of V5 master is exactly 28 sec; audio copied bit-for-bit.
complex_filter=(
    "[0:v]format=yuv420p[base];"
    "[1:v]format=rgba[iphone];"
    "[base][iphone]overlay=x=0:y=0:enable='gte(t,14)*lt(t,18)':shortest=1[s1];"
    "[2:v]format=rgba[hook1];"
    "[s1][hook1]overlay=x=0:y=0:enable='gte(t,0.06)*lt(t,2.43)':shortest=1[s2];"
    "[3:v]format=rgba[hook2];"
    "[s2][hook2]overlay=x=0:y=0:enable='gte(t,2.43)*lt(t,4.47)':shortest=1[s3];"
    "[s3]ass=/tmp/bohanes-v6-work/titulky-cs.ass[v]"
)
Path('/tmp/bohanes-v6-work').mkdir(exist_ok=True)
import shutil
shutil.copy2(SUB,'/tmp/bohanes-v6-work/titulky-cs.ass')
ff("-loglevel","warning",
   "-i",V5,
   "-loop","1","-framerate","30","-i",PNG,
   "-loop","1","-framerate","30","-i",HOOKS[0],
   "-loop","1","-framerate","30","-i",HOOKS[1],
   "-filter_complex",complex_filter,
   "-map","[v]","-map","0:a:0",
   "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p","-r","30",
   "-c:a","copy","-t","28","-movflags","+faststart",MASTER)
# Smaller 720p web preview, keeping all frames and the original audio.
ff("-loglevel","warning","-i",MASTER,"-vf","scale=720:1280:flags=lanczos",
   "-c:v","libx264","-preset","fast","-crf","22","-pix_fmt","yuv420p",
   "-c:a","copy","-movflags","+faststart",WEB)
def ffprobe(path):
    x=subprocess.run([F,"-hide_banner","-i",str(path)],capture_output=True,text=True)
    return x.stderr
print("MASTER",MASTER,MASTER.stat().st_size)
print("WEB",WEB,WEB.stat().st_size)
for p in [V5,MASTER,WEB]:
    txt=ffprobe(p)
    print(p.name,txt[-600:])
