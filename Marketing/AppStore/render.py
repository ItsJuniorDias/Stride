#!/usr/bin/env python3
"""App Store screenshots as one panorama per device, cut into slides.

Each device's slides are laid out side by side on one page so the background
glow and the route line run across the cuts: the next slide peeks in the store.
Chrome renders the page, slice.swift cuts it into opaque PNGs.

    python3 Marketing/AppStore/render.py

Swap a screenshot in shots/ or edit SLIDES and run it again.
"""
import html
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SHOTS = ROOT / "shots"
OUT = ROOT / "out"
BUILD = ROOT / ".build"
ICON = ROOT.parent.parent / "Stride/Stride/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SLIDES = [
    ("run-setup", "GPS run tracker", "Hit start.<br>We do <em>the rest</em>",
     "Pace, splits and auto-pause, on iPhone or Apple Watch."),
    ("countdown", "Voice coach", "A coach<br><em>in your ear</em>",
     "Splits, goals and pace alerts, spoken over your music."),
    ("progress", "Progress", "See how far<br><em>you've come</em>",
     "Stats, streaks and personal records that grow with every run."),
    ("home", "Your week", "Your week<br><em>at a glance</em>",
     "A weekly goal, streaks and plans from First 5K to the half."),
    ("share", "Instagram Stories", "Made for<br><em>your Story</em>",
     "Share a run as a card, your route, a photo or a sticker."),
    ("profile", "Stride Pro", "Go further<br><em>with Pro</em>",
     "Adaptive plans, intervals on your wrist and race predictions. Free for 7 days."),
]

# CSS size of one slide, device scale factor, and the layout inside it.
DEVICES = {
    "iphone-6.5": dict(w=414, h=896, scale=3, top=58, eyebrow=13, title=40, sub=17, sub_w=330,
                       phone_w=292, phone_top=282),
    "ipad-13": dict(w=1032, h=1376, scale=2, top=96, eyebrow=20, title=68, sub=26, sub_w=800,
                    phone_w=470, phone_top=440),
}

SHOT_RATIO = 1600 / 738  # height / width of the screenshots


def phone(x, y, width, shot):
    bezel = width * 0.034
    screen_w = width - 2 * bezel
    height = screen_w * SHOT_RATIO + 2 * bezel
    radius = screen_w * 0.14 + bezel
    island_w, island_h = screen_w * 0.30, screen_w * 0.088
    button = lambda side, top, length: (
        f'<i class="btn" style="{side}:{-bezel * 0.28:.1f}px;top:{top * height:.1f}px;'
        f'height:{length * height:.1f}px;width:{bezel * 0.34:.1f}px"></i>')
    return f"""
<div class="phone" style="left:{x - width / 2:.1f}px;top:{y:.1f}px;width:{width:.1f}px;height:{height:.1f}px;
     border-radius:{radius:.1f}px;padding:{bezel:.1f}px">
  {button("left", 0.17, 0.035)}{button("left", 0.24, 0.065)}{button("left", 0.32, 0.065)}{button("right", 0.26, 0.10)}
  <img src="{(SHOTS / (shot + '.jpg')).as_uri()}" style="border-radius:{radius - bezel:.1f}px">
  <i class="island" style="top:{bezel + screen_w * 0.028:.1f}px;width:{island_w:.1f}px;height:{island_h:.1f}px"></i>
</div>""", height


def route(total_w, d, ys):
    """A smooth running route crossing every cut at the given heights."""
    w = d["w"]
    pts = [(-40, ys[0])]
    for i in range(1, len(SLIDES)):
        pts.append((i * w, ys[i]))
    pts.append((total_w + 40, ys[-1]))
    path = f"M{pts[0][0]},{pts[0][1]}"
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx = (x1 - x0) * 0.5
        path += f" C{x0 + dx:.1f},{y0:.1f} {x1 - dx:.1f},{y1:.1f} {x1:.1f},{y1:.1f}"
    s = w / 414
    return f"""
<svg class="route" width="{total_w}" height="{d['h']}" viewBox="0 0 {total_w} {d['h']}">
  <path d="{path}" stroke="#FF6B47" stroke-opacity=".35" stroke-width="{22 * s:.1f}" fill="none" filter="url(#blur)"/>
  <path d="{path}" stroke="#0B0E12" stroke-width="{11 * s:.1f}" fill="none" stroke-linecap="round"/>
  <path d="{path}" stroke="#FF6B47" stroke-width="{6 * s:.1f}" fill="none" stroke-linecap="round"/>
  <defs><filter id="blur" x="-10%" y="-50%" width="120%" height="200%"><feGaussianBlur stdDeviation="{10 * s:.1f}"/></filter></defs>
</svg>"""


def page(name, d):
    w, h = d["w"], d["h"]
    total = w * len(SLIDES)
    s = w / 414
    ys = [h * f for f in (0.80, 0.56, 0.74, 0.50, 0.70, 0.54, 0.78)]
    parts = [route(total, d, ys)]
    for i in range(len(SLIDES) + 1):
        gx = i * w + (w * 0.08 if i % 2 else -w * 0.06)
        gy = h * (0.42 if i % 2 else 0.68)
        size = w * 1.25
        parts.append(f'<i class="glow" style="left:{gx - size / 2:.1f}px;top:{gy - size / 2:.1f}px;'
                     f'width:{size:.1f}px;height:{size:.1f}px"></i>')
    for i, (shot, eyebrow, title, sub) in enumerate(SLIDES):
        x0 = i * w
        icon = (f'<img class="icon" src="{ICON.as_uri()}" style="width:{d["eyebrow"] * 2.2:.1f}px;'
                f'height:{d["eyebrow"] * 2.2:.1f}px;border-radius:{d["eyebrow"] * 0.5:.1f}px">') if i == 0 else ""
        parts.append(f"""
<section style="left:{x0}px;top:{d['top']}px;width:{w}px">
  <p class="eyebrow" style="font-size:{d['eyebrow']}px">{icon}<span>{html.escape(eyebrow)}</span></p>
  <h1 style="font-size:{d['title']}px">{title}</h1>
  <p class="sub" style="font-size:{d['sub']}px;max-width:{d['sub_w']}px">{html.escape(sub)}</p>
</section>""")
        markup, _ = phone(x0 + w / 2, d["phone_top"], d["phone_w"], shot)
        parts.append(markup)
    start_y = ys[0] + 0
    parts.append(f'<i class="dot" style="left:{w * 0.07:.1f}px;top:{h * 0.80:.1f}px;'
                 f'width:{16 * s:.1f}px;height:{16 * s:.1f}px;border-width:{4 * s:.1f}px"></i>')
    doc = f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;padding:0;background:#0B0E12}}
body{{width:{total}px;height:{h}px;position:relative;overflow:hidden;
  background:linear-gradient(180deg,#141A22 0%,#0E1217 45%,#0B0E12 100%);
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","Helvetica Neue",sans-serif;
  -webkit-font-smoothing:antialiased}}
.glow{{position:absolute;border-radius:50%;
  background:radial-gradient(closest-side,rgba(255,107,71,.30),rgba(255,107,71,.10) 45%,rgba(255,107,71,0) 100%)}}
.route{{position:absolute;left:0;top:0}}
section{{position:absolute;text-align:center;box-sizing:border-box;padding:0 {24 * s:.0f}px}}
.eyebrow{{margin:0;color:#FF6B47;font-weight:800;letter-spacing:.16em;text-transform:uppercase;
  font-stretch:expanded;display:flex;align-items:center;justify-content:center;gap:.6em}}
.icon{{display:block}}
h1{{margin:.42em 0 0;color:#F2F4F0;font-weight:800;line-height:1.04;letter-spacing:-.02em}}
h1 em{{font-style:normal;color:#FF6B47}}
.sub{{margin:.8em auto 0;color:#9BA5B3;line-height:1.35;font-weight:500}}
.phone{{position:absolute;box-sizing:border-box;background:#05070A;
  box-shadow:0 0 0 {1.5 * s:.1f}px #353B45,0 0 0 {3 * s:.1f}px #0B0E12,0 {30 * s:.0f}px {70 * s:.0f}px rgba(0,0,0,.65),
  0 0 {90 * s:.0f}px rgba(255,107,71,.12)}}
.phone img{{display:block;width:100%;height:100%;object-fit:cover}}
.island{{position:absolute;left:50%;transform:translateX(-50%);background:#000;border-radius:999px}}
.btn{{position:absolute;background:#2A3039;border-radius:2px}}
.dot{{position:absolute;box-sizing:content-box;border-radius:50%;background:#FF6B47;border:solid #F2F4F0;
  transform:translate(-50%,-50%);box-shadow:0 0 {18 * s:.0f}px rgba(255,107,71,.8)}}
</style></head><body>{''.join(parts)}</body></html>"""
    BUILD.mkdir(exist_ok=True)
    file = BUILD / f"{name}.html"
    file.write_text(doc)
    return file, total


def screenshot(file, panorama, total, d):
    """Headless Chrome writes the screenshot but doesn't always quit, so stop it once the file is done."""
    panorama.unlink(missing_ok=True)
    chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                               f"--user-data-dir={BUILD / ('chrome-' + panorama.stem)}", f"--force-device-scale-factor={d['scale']}",
                               f"--window-size={total},{d['h']}", f"--screenshot={panorama}", file.as_uri()],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    size, deadline = -1, time.time() + 120
    while time.time() < deadline and chrome.poll() is None:
        time.sleep(1)
        if panorama.exists() and panorama.stat().st_size == size > 0:
            break
        size = panorama.stat().st_size if panorama.exists() else -1
    chrome.terminate()
    chrome.wait()
    subprocess.run(["pkill", "-f", str(BUILD / ('chrome-' + panorama.stem))], check=False)
    if not panorama.exists():
        raise SystemExit(f"Chrome didn't render {file.name}")


def main():
    OUT.mkdir(exist_ok=True)
    for name, d in DEVICES.items():
        file, total = page(name, d)
        panorama = BUILD / f"{name}.png"
        screenshot(file, panorama, total, d)
        names = [f"{i + 1:02d}-{s[0]}" for i, s in enumerate(SLIDES)]
        subprocess.run(["swift", str(ROOT / "slice.swift"), str(panorama), str(OUT / name),
                        str(d["w"] * d["scale"]), str(d["h"] * d["scale"]), *names], check=True)


if __name__ == "__main__":
    main()
