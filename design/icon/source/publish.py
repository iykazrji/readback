"""Publish the selected plates, menu bar templates and comparison sheet.

From the project root, use python3 source/publish.py --rebuild to render from
geometry. Without the flag, publish the full-size plates already in studies/.
"""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path
from finish import ROOT, FONT, finish, im

SELECTION=["cadence","undertone","reed"]
PLATES=ROOT/"studies"/"round-3"
FINAL=ROOT/"final"

def contact(names=SELECTION, labels=None, filename="contact.png", subtitle="macOS app icon studies"):
    labels = labels or [name.title() for name in names]
    margin, field, top, row = 164, 526, 134, 266
    width, height = margin+2*field, top+len(names)*row+12
    args=["-size", f"{width}x{height}", "xc:#ececec",
          "-fill","#1e1e1e","-draw",f"rectangle {margin+field},76 {width},{height}",
          "-fill","#f8f8f6","-draw",f"rectangle 0,0 {width},75",
          "-font",FONT,"-pointsize","36","-fill","#1b1b1c","-draw","text 28,50 'Readback'",
          "-pointsize","17","-fill","#565657","-draw",f"text 218,48 '{subtitle}'"]
    with tempfile.TemporaryDirectory() as d:
        for j,(color,appearance) in enumerate([("#303033","Light"),("#ededed","Dark")]):
            x=margin+j*field
            args += ["-fill",color,"-pointsize","14","-draw",f"text {x+17},103 '{appearance}'"]
            for size,centre in [(256,135),(64,325),(32,409),(16,483)]:
                label=f"{size} px"
                args += ["-pointsize","12","-draw",f"text {x+centre-len(label)*3},126 '{label}'"]
                for i,name in enumerate(names):
                    dest=Path(d)/f"{name}-{size}.miff"
                    if not dest.exists():
                        im(FINAL/f"{name}.png","-filter","Lanczos","-resize",f"{size}x{size}",dest)
                    cy=top+row*i+row//2
                    args += [dest,"-geometry",f"+{x+centre-size//2}+{cy-size//2}",
                             "-compose","over","-composite"]
        for i,name in enumerate(names):
            args += ["-fill","#28282a","-pointsize","22","-draw",
                     f"text 29,{top+row*i+row//2+8} '{labels[i]}'"]
        im(*args,"-strip",FINAL/filename)

def retain_housing(folder, previous, output):
    # The 6.35-unit template camera covers 635 pixels of the full-size plate.
    # Inset its matte two pixels so the existing antialiased lips also survive.
    with tempfile.TemporaryDirectory() as directory:
        matte = Path(directory)/"brass.miff"
        im(folder/"cadence-brass-ink.png","-alpha","extract","-filter","Box",
           "-resize","635x635","-gravity","center","-background","black",
           "-extent","1024x1024","-morphology","Erode","Disk:2",matte)
        im(previous,"(",folder/"cadence-brass.png",matte,"-compose","CopyOpacity",
           "-composite",")","-compose","over","-composite","-depth","8",
           "-strip","-define","png:color-type=6",output)

def publish(names, folder, rebuild, *, options=(), export_names=None):
    exports = export_names or names
    cmd = ["blender","-b","-t","14","-noaudio","--python-exit-code","1","--python",
           str(ROOT/"source"/"render.py"),"--","3",*names,*options]
    if rebuild:
        subprocess.run(cmd,check=True)
    subprocess.run([*cmd,"--templates"],check=True)
    for name, export in zip(names, exports):
        finish(folder,name)
        if export == "cadence-brass":
            retain_housing(folder, FINAL/"cadence-brass-grainy.png", FINAL/f"{export}.png")
        else:
            shutil.copyfile(folder/f"{name}.png",FINAL/f"{export}.png")
        for size,suffix in [(18,""),(36,"@2x")]:
            # Resize just coverage; all foreground pixels remain pure black.
            coverage_filter = "Box" if name == "cadence-brass" else "Lanczos"
            im(folder/f"{name}-ink.png","-alpha","extract","-filter",coverage_filter,
               "-resize",f"{size}x{size}","-write","mpr:coverage","+delete",
               "-size",f"{size}x{size}","xc:black","mpr:coverage","-compose",
               "CopyOpacity","-composite","-depth","8","-define","png:color-type=6",
               "-strip",FINAL/f"{export}-menubar{suffix}.png")


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--rebuild",action="store_true")
    p.add_argument("--cadence-brass",action="store_true",help="Publish the brass refinements of Cadence")
    args=p.parse_args()
    FINAL.mkdir(exist_ok=True)
    if args.cadence_brass:
        previous = FINAL/"cadence-brass-grainy.png"
        if not previous.exists():
            shutil.copyfile(ROOT/"studies"/"cadence-brass"/"pass-5"/"cadence-brass.png",previous)
        for number, export in [(6,"cadence-brass"), (4,"cadence-brass-a")]:
            folder = ROOT/"studies"/"cadence-brass"/f"pass-{number}"
            publish(["cadence-brass"], folder, args.rebuild,
                    options=["--brass-pass",str(number)], export_names=[export])
        contact(["cadence-brass","cadence-brass-a","cadence","reed"],
                ["Cadence brass","A · Crisper folds","Cadence silver","Reed"],
                "cadence-brass-contact.png","Cadence in brushed brass")
    else:
        publish(SELECTION, PLATES, args.rebuild)
        contact()

if __name__=="__main__":
    main()
