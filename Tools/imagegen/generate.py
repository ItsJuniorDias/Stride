#!/usr/bin/env python3
"""Generate images for the Stride app with OpenRouter and Google's Nano Banana
(Gemini 2.5 Flash Image).

The catalog (assets.json) holds one shared style, so every image matches the
design system, plus a prompt and aspect ratio per image.

    export OPENROUTER_API_KEY=sk-or-...        # or put it in Tools/imagegen/.env
    python3 Tools/imagegen/generate.py --list
    python3 Tools/imagegen/generate.py plan-first-5k empty-friends --variants 3
    python3 Tools/imagegen/generate.py --all
    python3 Tools/imagegen/generate.py --name hero --aspect 16:9 --prompt "A runner at dusk"
    python3 Tools/imagegen/generate.py plan-10k --reference Design/Images/plan-first-5k-1.png
    python3 Tools/imagegen/generate.py empty-friends --install      # also into Assets.xcassets

Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
CATALOG = HERE / "assets.json"
DEFAULT_OUT = REPO / "Design" / "Images"
ASSET_CATALOG = REPO / "Stride" / "Stride" / "Assets.xcassets"
ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "google/gemini-2.5-flash-image"
ASPECTS = {"1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"}


def api_key() -> str:
    """OPENROUTER_API_KEY from the environment, or from Tools/imagegen/.env."""
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    env_file = HERE / ".env"
    if not key and env_file.exists():
        for line in env_file.read_text().splitlines():
            if line.strip().startswith("OPENROUTER_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("Set OPENROUTER_API_KEY (or add it to Tools/imagegen/.env).")
    return key


def load_catalog() -> dict:
    with CATALOG.open() as file:
        return json.load(file)


def data_url(path: Path) -> str:
    """A local image as a data URL, for use as a style reference."""
    mime = "image/jpeg" if path.suffix.lower() in {".jpg", ".jpeg"} else "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def request_image(key: str, model: str, prompt: str, aspect: str, reference: Path | None,
                  retries: int = 4) -> tuple[bytes, str]:
    """One image from OpenRouter. Returns the image bytes and any text the model added."""
    content: list[dict] | str = prompt
    if reference:
        content = [
            {"type": "text", "text": "Match the style, palette and rendering of the reference image exactly. " + prompt},
            {"type": "image_url", "image_url": {"url": data_url(reference)}},
        ]
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "modalities": ["image", "text"],
        "image_config": {"aspect_ratio": aspect},
    }
    body = json.dumps(payload).encode()
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/ItsJuniorDias/Stride",
        "X-Title": "Stride image generator",
    }
    delay = 4.0
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(urllib.request.Request(ENDPOINT, data=body, headers=headers), timeout=180) as response:
                result = json.load(response)
            message = result["choices"][0]["message"]
            images = message.get("images") or []
            if not images:
                raise RuntimeError(f"No image in the response: {(message.get('content') or '')[:200]!r}")
            url = images[0]["image_url"]["url"]
            match = re.match(r"data:image/[\w.+-]+;base64,(.*)", url, re.S)
            if not match:
                raise RuntimeError("The image came back in an unexpected format.")
            return base64.b64decode(match.group(1)), message.get("content") or ""
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            # Rate limits and server errors are worth another try; anything else isn't.
            if error.code in (408, 429, 500, 502, 503, 504) and attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise RuntimeError(f"HTTP {error.code}: {detail}") from None
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise RuntimeError(f"Network error: {error}") from None
    raise RuntimeError("Gave up after several attempts.")


def asset_name(name: str) -> str:
    """plan-first-5k -> planFirst5k, the name used in the asset catalog and in code."""
    parts = re.split(r"[-_\s]+", name)
    return parts[0].lower() + "".join(part[:1].upper() + part[1:] for part in parts[1:])


def install(image: Path, name: str, max_side: int = 1024) -> Path:
    """Puts an image into Assets.xcassets as a single-scale image set, as a JPEG no larger than
    `max_side` pixels (the PNGs are over 1 MB each; the JPEGs are a tenth of that)."""
    image_set = ASSET_CATALOG / f"{asset_name(name)}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    for old in list(image_set.glob("*.png")) + list(image_set.glob("*.jpg")):
        old.unlink()
    target = image_set / f"{name}.jpg"
    subprocess.run(["sips", "-Z", str(max_side), "-s", "format", "jpeg", "-s", "formatOptions", "82",
                    str(image), "--out", str(target)], check=True, capture_output=True)
    contents = {"images": [{"filename": target.name, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (image_set / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    return image_set


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Stride images with OpenRouter + Nano Banana.")
    parser.add_argument("names", nargs="*", help="Images from assets.json to generate.")
    parser.add_argument("--all", action="store_true", help="Generate every image in the catalog.")
    parser.add_argument("--list", action="store_true", help="List the catalog and exit.")
    parser.add_argument("--prompt", help="A one-off prompt instead of catalog entries (needs --name).")
    parser.add_argument("--name", help="File name for a one-off prompt.")
    parser.add_argument("--aspect", default=None, help=f"Aspect ratio: {', '.join(sorted(ASPECTS))}.")
    parser.add_argument("--variants", type=int, default=1, help="Images per entry (default 1).")
    parser.add_argument("--reference", type=Path, help="An image whose style the new ones should match.")
    parser.add_argument("--no-style", action="store_true", help="Leave out the shared style from assets.json.")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"OpenRouter model (default {DEFAULT_MODEL}).")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output folder (default Design/Images).")
    parser.add_argument("--install", action="store_true", help="Also put the first variant into Assets.xcassets.")
    parser.add_argument("--pick", type=int, default=1, help="Which variant --install uses (default 1).")
    parser.add_argument("--workers", type=int, default=3, help="Requests at the same time (default 3).")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be sent, without calling the API.")
    args = parser.parse_args()

    catalog = load_catalog()
    entries = {entry["name"]: entry for entry in catalog["assets"]}

    if args.list:
        for entry in catalog["assets"]:
            print(f"{entry['name']:<22} {entry['aspect']:>5}  {entry['use']}")
        return

    jobs: list[dict] = []
    if args.prompt:
        if not args.name:
            sys.exit("--prompt needs --name.")
        jobs.append({"name": args.name, "prompt": args.prompt, "aspect": args.aspect or "1:1"})
    else:
        names = list(entries) if args.all else args.names
        if not names:
            sys.exit("Name some images (see --list), or use --all or --prompt.")
        unknown = [name for name in names if name not in entries]
        if unknown:
            sys.exit(f"Not in assets.json: {', '.join(unknown)}")
        for name in names:
            entry = entries[name]
            jobs.append({"name": name, "prompt": entry["prompt"], "aspect": args.aspect or entry["aspect"],
                         "style": entry.get("style", True)})

    for job in jobs:
        if job["aspect"] not in ASPECTS:
            sys.exit(f"{job['name']}: aspect ratio {job['aspect']} isn't supported.")
        # Entries with "style": false (e.g. an icon on a colored background) bring their own style.
        if not args.no_style and job.get("style", True):
            job["prompt"] = f"{job['prompt']}\n\nStyle: {catalog['style']}"
    if args.reference and not args.reference.exists():
        sys.exit(f"Reference image not found: {args.reference}")

    tasks = [(job, variant) for job in jobs for variant in range(1, max(args.variants, 1) + 1)]
    if args.dry_run:
        for job, variant in tasks:
            print(f"--- {job['name']} #{variant} ({job['aspect']}, {args.model})\n{job['prompt']}\n")
        return

    key = api_key()
    args.out.mkdir(parents=True, exist_ok=True)

    def run(job: dict, variant: int) -> tuple[str, Path]:
        image, note = request_image(key, args.model, job["prompt"], job["aspect"], args.reference)
        suffix = f"-{variant}" if args.variants > 1 else ""
        path = args.out / f"{job['name']}{suffix}.png"
        path.write_bytes(image)
        # How the image was made, to regenerate or tweak it later.
        path.with_suffix(".json").write_text(json.dumps({
            "name": job["name"], "variant": variant, "model": args.model, "aspect": job["aspect"],
            "prompt": job["prompt"], "reference": str(args.reference) if args.reference else None,
            "note": note, "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }, indent=2) + "\n")
        return job["name"], path

    failures = 0
    first: dict[str, Path] = {}
    with ThreadPoolExecutor(max_workers=max(args.workers, 1)) as pool:
        futures = {pool.submit(run, job, variant): (job["name"], variant) for job, variant in tasks}
        for future in as_completed(futures):
            name, variant = futures[future]
            try:
                _, path = future.result()
                print(f"✓ {path.relative_to(REPO) if path.is_relative_to(REPO) else path}")
                if variant == args.pick:
                    first[name] = path
            except Exception as error:  # noqa: BLE001 - report every failure and carry on
                failures += 1
                print(f"✗ {name} #{variant}: {error}", file=sys.stderr)

    if args.install:
        for name, path in first.items():
            print(f"→ Assets.xcassets/{install(path, name).name}")

    if failures:
        sys.exit(f"{failures} image(s) failed.")


if __name__ == "__main__":
    main()
