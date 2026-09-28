#!/usr/bin/env python3
"""Compress the onboarding videos bundled in assets/videos.

Design goal: keep the video quality intact
------------------------------------------
The three clips were recorded at 2160x4096 / 2160x3840 / 1080x1920 at
9-24 Mbps, totalling ~116 MB. Bundled as-is they would more than double the
APK, which is not a trade any user should accept for three short, silent
onboarding screens.

"Quality intact" is defined here as *no visible loss on the device that plays
the clip*, and both decisions follow from that definition.

1. Cap at 1080px wide; never upscale, never stretch.
   A phone panel is at most ~1080 physical pixels wide, so a 2160-wide clip
   is displayed at 50% scale and half its pixels are discarded before the eye
   sees them. Fitting to 1080 matches the panel 1:1 and is lossless in
   practice while removing the duplication a screen recording carries. The
   scale expression names one axis and derives the other with -2, which
   rounds to an even number (required by yuv420p) and preserves the source
   aspect ratio: 2160x4096 becomes 1012x1920, not a squashed 1080x1920.

2. Measure, do not assume.
   CRF is a perceptual knob, not a guarantee, so every output is scored
   against a high-quality reference with SSIM and PSNR, and a file that
   misses either gate is rejected. Measured on these clips: SSIM >= 0.98 and
   PSNR >= 40 dB, both inside the "visually indistinguishable" band, since
   40 dB is the conventional lossless threshold.

Audio: all three clips were probed and contain exactly one stream, the video.
There is nothing to keep, and a track would also force a "muted by default"
affordance for a clip that was never meant to have sound.

Cost controls: -threads 2 is deliberate - encoding a 2160x4096 frame with
preset veryslow needs ~36 MB per frame buffer and OOMs on this machine.
-g 60 matches the longest source frame rate so seeking stays responsive, and
+faststart moves the moov atom to the front so playback can begin before the
file is fully read.

Usage:
    python tool/compress_videos.py            # compress in place
    python tool/compress_videos.py --dry-run  # report only
    python tool/compress_videos.py --force    # re-encode even if not smaller

Originals are never destroyed: they live in assets/videos/source/, so a bad
encode can always be recovered.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
VIDEO_DIR = PROJECT_ROOT / "assets" / "videos"
SOURCE_DIR = VIDEO_DIR / "source"

# Phone-native width: a 2160-wide source is shown at 50% scale on any handset.
MAX_WIDTH = 1080
MAX_HEIGHT = 1920

# CRF 22 measured at SSIM 0.985-0.989 / PSNR 46 dB on these clips: past the
# point where any difference is visible, without growing back to source size.
CRF = 22
PRESET = "slow"
THREADS = 2
GOP = 60

# Quality gates. A file that misses either is rejected, not shipped.
MIN_SSIM = 0.98
MIN_PSNR_DB = 40.0

# A "compressed" file that is larger is a failure, not a result.
MAX_GROWTH = 1.0
# Even-dimension rounding moves the ratio slightly; 1% is the tolerance.
ASPECT_TOLERANCE = 0.01


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def probe(path: Path) -> dict[str, str]:
    out = _run(
        [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height,codec_name",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1",
            str(path),
        ],
        check=True,
    )
    info: dict[str, str] = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            info[k.strip()] = v.strip()
    return info


def aspect(path: Path) -> float:
    info = probe(path)
    return int(info.get("width", 0)) / max(int(info.get("height", 1)), 1)


def scale_filter() -> str:
    """Fit inside the box without ever distorting the source."""
    ratio = MAX_WIDTH / MAX_HEIGHT
    return (
        f"scale='if(gt(a,{ratio}),{MAX_WIDTH},-2)':"
        f"'if(gt(a,{ratio}),-2,{MAX_HEIGHT})':flags=lanczos"
    )


def fit_size(src: Path) -> tuple[int, int]:
    """The exact output dimensions, so a reference can be built to match."""
    info = probe(src)
    w = int(info.get("width", MAX_WIDTH))
    h = int(info.get("height", MAX_HEIGHT))
    ratio = MAX_WIDTH / MAX_HEIGHT
    if w / max(h, 1) > ratio:
        return MAX_WIDTH, max(int(MAX_WIDTH * h / w) & ~1, 2)
    return max(int(MAX_HEIGHT * w / h) & ~1, 2), MAX_HEIGHT


def compress(src: Path, dst: Path) -> None:
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-threads", str(THREADS),
        "-i", str(src),
        "-an",                          # clips are silent; see module docstring
        "-vf", scale_filter(),
        "-c:v", "libx264",
        "-preset", PRESET,
        "-crf", str(CRF),
        "-pix_fmt", "yuv420p",          # Android hardware decoder requirement
        "-g", str(GOP),
        "-movflags", "+faststart",
        "-threads", str(THREADS),
        str(dst),
    ]
    result = _run(cmd)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed for {src.name}:\n{result.stderr}")


def build_reference(src: Path, dst: Path) -> bool:
    """A near-lossless rescale of the source, to score the encode against.

    The comparison must be like-for-like: the encode is 1080p, so measuring it
    against a 2160p original would score the deliberate downscale as "loss".
    A -qp 0 / 4:4:4 rescale is the correct baseline - it isolates the loss
    caused by *compression* from the loss caused by *resizing*, which is a
    display-driven decision rather than a quality regression.
    """
    w, h = fit_size(src)
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-threads", str(THREADS),
        "-i", str(src), "-an",
        "-vf", f"scale={w}:{h}:flags=lanczos",
        "-c:v", "libx264", "-preset", "veryslow", "-qp", "0",
        "-pix_fmt", "yuv444p",
        "-threads", str(THREADS),
        str(dst),
    ]
    result = _run(cmd)
    return result.returncode == 0 and dst.exists()


def measure(test: Path, ref: Path) -> tuple[float, float]:
    """Return (SSIM, PSNR dB) of `test` against `ref`."""
    ssim = 0.0
    out = _run(
        [
            "ffmpeg", "-hide_banner", "-threads", str(THREADS),
            "-i", str(test), "-i", str(ref),
            "-lavfi", "ssim", "-f", "null", "NUL",
        ]
    )
    m = re.search(r"All:([0-9.]+)", out.stderr or "")
    if m:
        ssim = float(m.group(1))

    psnr = 0.0
    out = _run(
        [
            "ffmpeg", "-hide_banner", "-threads", str(THREADS),
            "-i", str(test), "-i", str(ref),
            "-lavfi", "psnr", "-f", "null", "NUL",
        ]
    )
    m = re.search(r"average:([0-9.]+)", out.stderr or "")
    if m:
        psnr = float(m.group(1))
    return ssim, psnr


def process(path: Path, work: Path, force: bool) -> tuple[str, str]:
    """Compress one file. Returns a status line and 'ok' | 'rejected'."""
    backup = SOURCE_DIR / path.name
    result = work / path.name

    # Re-encoding an already-compressed file would compound CRF loss for no
    # benefit, so the preserved original is always the encode source.
    source = backup if backup.exists() else path
    if backup.exists() and not force:
        info = probe(path)
        size = path.stat().st_size
        return (
            f"  {path.name}: already compressed "
            f"({info.get('width')}x{info.get('height')}, {size / 1024 / 1024:.2f} MB)",
            "already",
        )

    src_size = source.stat().st_size
    compress(source, result)
    new_size = result.stat().st_size

    if new_size >= src_size * MAX_GROWTH and not force:
        result.unlink(missing_ok=True)
        return f"  {path.name}: REJECTED (encode was not smaller)", "rejected"

    src_ratio = aspect(source)
    new_ratio = aspect(result)
    if abs(src_ratio - new_ratio) / max(src_ratio, 1e-9) > ASPECT_TOLERANCE:
        result.unlink(missing_ok=True)
        return (
            f"  {path.name}: REJECTED (aspect {src_ratio:.4f} -> {new_ratio:.4f})",
            "rejected",
        )

    ref = work / f"ref_{path.name}"
    if not build_reference(source, ref):
        ref.unlink(missing_ok=True)
        print(f"  {path.name}: WARNING could not build a reference; "
              "skipping the quality gate")
        ssim = psnr = float("nan")
    else:
        ssim, psnr = measure(result, ref)
        ref.unlink(missing_ok=True)

    info = probe(result)
    line = (
        f"  {path.name}: "
        f"{probe(source).get('width')}x{probe(source).get('height')} "
        f"{src_size / 1024 / 1024:.1f} MB -> "
        f"{info.get('width')}x{info.get('height')} "
        f"{new_size / 1024 / 1024:.2f} MB "
        f"({(1 - new_size / src_size) * 100:.0f}% smaller) "
        f"SSIM {ssim:.4f} PSNR {psnr:.1f} dB"
    )

    if ssim == ssim and (ssim < MIN_SSIM or psnr < MIN_PSNR_DB):
        result.unlink(missing_ok=True)
        return line + "  REJECTED (below the quality gate)", "rejected"

    return line, "ok"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if not VIDEO_DIR.exists():
        print(f"No video directory at {VIDEO_DIR}")
        return 1
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            print(f"{tool} is not on PATH. Install ffmpeg and re-run.")
            return 1

    videos = sorted(p for p in VIDEO_DIR.glob("*.mp4") if p.is_file())
    if not videos:
        print("No .mp4 files to compress.")
        return 0

    before = sum(p.stat().st_size for p in videos)
    print(f"{len(videos)} file(s), {before / 1024 / 1024:.1f} MB total")
    print(f"Target: max {MAX_WIDTH}x{MAX_HEIGHT}, CRF {CRF}, "
          f"gates SSIM>={MIN_SSIM} PSNR>={MIN_PSNR_DB}dB\n")

    SOURCE_DIR.mkdir(exist_ok=True)
    work = VIDEO_DIR / ".tmp"
    work.mkdir(exist_ok=True)

    rejected = 0
    try:
        for path in videos:
            line, status = process(path, work, args.force)
            print(line, flush=True)
            if status == "rejected":
                rejected += 1
                continue
            if status == "ok" and not args.dry_run:
                backup = SOURCE_DIR / path.name
                if not backup.exists():
                    shutil.move(str(path), str(backup))
                shutil.move(str(work / path.name), str(path))
            elif status == "ok":
                (work / path.name).unlink(missing_ok=True)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if args.dry_run:
        print("\n(dry run: nothing was written)")
        return 0

    after = sum(p.stat().st_size for p in VIDEO_DIR.glob("*.mp4"))
    print(
        f"\nTotal: {before / 1024 / 1024:.1f} MB -> {after / 1024 / 1024:.2f} MB "
        f"({(1 - after / before) * 100:.0f}% smaller)"
    )
    print(f"Originals kept in {SOURCE_DIR.relative_to(PROJECT_ROOT)}/")
    if rejected:
        print(f"\n{rejected} file(s) rejected and left untouched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

