"""Composite the housing shadow, downsample and make the native-size proof sheet."""
import argparse
import subprocess as sp
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES=["undertone","reed","cadence","dovetail"]
FONT="/System/Library/Fonts/Helvetica.ttc"

def im(*args):
    sp.run(["magick", *map(str,args)],check=True)

def finish(folder,name):
    plate=folder/f"{name}-plate.png"
    with tempfile.TemporaryDirectory() as d:
        alpha=Path(d)/"alpha.miff"
        im(plate,"-alpha","extract",alpha)
        layers=[]
        for i,(dy,sigma,opacity) in enumerate([(16,15,.24),(4,3.5,.23)]):
            mask=Path(d)/f"s{i}.miff"
            im(alpha,"-virtual-pixel","black","-blur",f"0x{sigma}","-roll",f"+0+{dy}","-evaluate","multiply",opacity,mask)
            layers.extend(["(","-size","1024x1024","xc:black",mask,"-compose","CopyOpacity","-composite",")"])
        im(*layers,"-compose","over","-composite",plate,"-composite","-depth","8","-strip","-define","png:color-type=6",folder/f"{name}.png")

def sheet(folder,names,path):
    # Each named row has a light and dark field at identical pixel positions.
    w,rh=1184,302
    with tempfile.TemporaryDirectory() as d:
        cmd=["-size",f"{w}x{rh*len(names)}","xc:#ececec","-fill","#1e1e1e","-draw",f"rectangle 592,0 1183,{rh*len(names)-1}"]
        for idx,name in enumerate(names):
            y=rh*idx
            for left,ink in [(0,"#292929"),(592,"#eeeeee")]:
                cmd += ["-font",FONT,"-pointsize","18","-fill",ink,"-draw",f"text {left+24},{y+33} '{name.title()}'"]
                for sz,cx in [(256,148),(64,347),(32,439),(16,521)]:
                    thumb=Path(d)/f"{name}-{sz}.miff"
                    if not thumb.exists():
                        im(folder/f"{name}.png","-filter","Lanczos","-resize",f"{sz}x{sz}",thumb)
                    cmd += [thumb,"-geometry",f"+{left+cx-sz//2}+{y+157-sz//2}","-compose","over","-composite",
                            "-font",FONT,"-pointsize","13","-fill",ink,"-draw",f"text {left+cx-7},{y+284} '{sz}'"]
        im(*cmd,"-strip",path)

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("round",type=int)
    p.add_argument("names",nargs="*",default=NAMES)
    a=p.parse_args()
    folder=ROOT/"studies"/f"round-{a.round}"
    for name in a.names:
        finish(folder,name)
    sheet(folder,a.names,folder/"proof.png")
