"""Extract the first decoded frame of each bundled video without changing originals.

Requires ffmpeg on PATH. Run from any directory after adding or replacing videos.
"""

from pathlib import Path
import shutil
import subprocess


def main():
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg is required to generate video covers.")
    videos = Path(__file__).resolve().parents[1] / "videos"
    covers = videos / "covers"
    covers.mkdir(exist_ok=True)
    sources = sorted(videos.glob("*.mp4"))
    for source in sources:
        subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
             "-frames:v", "1", "-q:v", "2", "-update", "1",
             str(covers / (source.stem + ".jpg"))],
            check=True,
        )
    print(f"Generated {len(sources)} first-frame video covers.")


if __name__ == "__main__":
    main()
