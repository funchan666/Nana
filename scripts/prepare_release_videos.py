"""Prepare smaller bundled videos without changing the supplied originals.

Requires ffmpeg with libx265 and ffprobe. Keeps resolution, cadence and audio;
uses CRF 20, then CRF 17 when full-video SSIM falls below 0.985. If a result
is larger or still below the quality floor, remuxes the original instead.
This is a media packaging utility, not an application build or test runner.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "videos"
OUTPUT = ROOT / "AppResources" / "videos"


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)
    ]))


def prepare(source):
    target = OUTPUT / source.name
    original = probe(source)
    ssim = 1.0
    mode = "original"
    for crf in (20, 17):
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(source),
            "-map", "0:v:0", "-map", "0:a?", "-map_metadata", "-1",
            "-c:v", "libx265", "-preset", "medium", "-crf", str(crf),
            "-x265-params", "pools=2:frame-threads=2:log-level=error",
            "-tag:v", "hvc1", "-c:a", "copy", "-movflags", "+faststart",
            str(target)
        ], check=True)
        comparison = subprocess.run([
            "ffmpeg", "-nostdin", "-v", "info", "-i", str(source), "-i", str(target),
            "-filter_complex", "[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim",
            "-an", "-f", "null", "-"
        ], capture_output=True, text=True, check=True)
        ssim = float(re.findall(r"All:([0-9.]+)", comparison.stderr)[-1])
        if ssim >= 0.985:
            mode = f"HEVC CRF {crf}"
            break
    if ssim < 0.985 or target.stat().st_size >= source.stat().st_size:
        subprocess.run([
            "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(source),
            "-map", "0:v:0", "-map", "0:a?", "-c", "copy", "-map_metadata", "-1",
            "-movflags", "+faststart", str(target)
        ], check=True)
        mode, ssim = "Original streams", 1.0
    result = probe(target)
    before = next(s for s in original["streams"] if s["codec_type"] == "video")
    after = next(s for s in result["streams"] if s["codec_type"] == "video")
    for key in ("width", "height", "avg_frame_rate", "nb_frames"):
        assert before[key] == after[key], (source.name, key)
    # Audio remains the original compressed packets, not another lossy encode.
    if any(s["codec_type"] == "audio" for s in original["streams"]):
        audio_hashes = [subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", str(p), "-map", "0:a:0", "-c", "copy",
            "-f", "hash", "-hash", "sha256", "-"
        ]).strip() for p in (source, target)]
        assert audio_hashes[0] == audio_hashes[1], source.name
    row = dict(file=source.name, source_bytes=source.stat().st_size,
               bundled_bytes=target.stat().st_size, encoding=mode, ssim=ssim,
               source_sha256=hashlib.sha256(source.read_bytes()).hexdigest())
    print(json.dumps(row), flush=True)
    return row


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE / "covers", OUTPUT / "covers", dirs_exist_ok=True)
    with ThreadPoolExecutor(max_workers=2) as pool:
        rows = list(pool.map(prepare, sorted(SOURCE.glob("*.mp4"))))
    (ROOT / "release-video-inventory.json").write_text(json.dumps(rows, indent=2) + "\n")
