"""Render Nana's original instrumental loops; no third-party recordings used.

Requires NumPy and macOS afconvert. This only authors bundled audio assets.
"""
from pathlib import Path
import subprocess
import tempfile
import wave
import numpy as np

DESTINATION = Path(__file__).resolve().parents[1] / "assets" / "room-music"
SAMPLE_RATE = 32000
TRACKS = [
    ("moonlit-keys", 72, [48, 53, 55, 48], [0, 4, 7, 11], 0),
    ("slow-sunday", 80, [50, 55, 48, 53], [0, 3, 7, 10], 1),
    ("city-lights", 90, [45, 53, 48, 55], [0, 4, 7, 9], 2),
    ("quiet-tides", 68, [48, 55, 57, 53], [0, 4, 7, 14], 3),
    ("little-sparks", 96, [53, 48, 55, 57], [0, 4, 7, 12], 4),
    ("after-hours", 76, [45, 50, 52, 45], [0, 3, 7, 10], 5),
]


def render(name, bpm, roots, chord, variation):
    beat = 60 / bpm
    length = round(32 * beat * SAMPLE_RATE)
    mix = np.zeros((length, 2), dtype=np.float64)
    rng = np.random.default_rng(20260922 + variation)

    def add(signal, at, gain, pan=0):
        indices = (round(at * SAMPLE_RATE) + np.arange(len(signal))) % length
        np.add.at(mix[:, 0], indices, signal * gain * np.sqrt((1 - pan) / 2))
        np.add.at(mix[:, 1], indices, signal * gain * np.sqrt((1 + pan) / 2))

    def note(midi, at, duration, gain, pad=False, pan=0):
        t = np.arange(round(duration * SAMPLE_RATE)) / SAMPLE_RATE
        frequency = 440 * 2 ** ((midi - 69) / 12)
        tone = np.sin(2 * np.pi * frequency * t)
        tone += (0.12 if pad else 0.28) * np.sin(2 * np.pi * frequency * 2 * t)
        envelope = (1 - np.exp(-t / (0.3 if pad else 0.012)))
        envelope *= np.exp(-t / (duration if pad else duration * 0.28))
        envelope *= np.minimum(1, (duration - t) / (0.3 if pad else 0.08))
        add(tone * envelope, at, gain, pan)

    for bar in range(8):
        root = roots[bar % 4]
        start = bar * 4 * beat
        for index, interval in enumerate(chord):
            note(root + interval, start, 4 * beat, 0.11, True, (index - 1.5) * 0.35)
        note(root - 12, start, 1.9 * beat, 0.28)
        note(root - 12, start + 2 * beat, 1.7 * beat, 0.20)
        pattern = [0, 2, 1, 3, 2, 1] if variation % 2 else [0, 1, 2, 3, 1, 2]
        for step, degree in enumerate(pattern):
            note(root + 12 + chord[degree], start + step * beat * 0.625,
                 1.7 * beat, 0.16, pan=(-0.3 if step % 2 else 0.3))
        if variation != 3:
            for step in range(4):
                t = np.arange(round(0.18 * SAMPLE_RATE)) / SAMPLE_RATE
                kick = np.sin(2 * np.pi * (48 * t + 6 * (1 - np.exp(-t * 35)))) * np.exp(-t * 28)
                if step % 2 == 0:
                    add(kick, start + step * beat, 0.13)
                noise = rng.normal(size=len(t))
                brush = (noise - np.roll(noise, 1)) * np.exp(-t * 65)
                add(brush, start + (step + 0.5) * beat, 0.018, 0.25)

    # Wrapped quiet echoes preserve the loop tails across the file boundary.
    dry = mix.copy()
    for delay, gain in [(0.187, 0.16), (0.313, 0.09), (0.479, 0.05)]:
        mix += np.roll(dry[:, ::-1], round(delay * SAMPLE_RATE), axis=0) * gain
    mix -= mix.mean(axis=0)
    mix *= 0.55 / max(np.max(np.abs(mix)), 0.001)
    edge = round(0.008 * SAMPLE_RATE)
    mix[:edge] *= np.linspace(0, 1, edge)[:, None]
    mix[-edge:] *= np.linspace(1, 0, edge)[:, None]
    with tempfile.TemporaryDirectory() as temporary:
        source = Path(temporary) / "loop.wav"
        with wave.open(str(source), "wb") as output:
            output.setnchannels(2)
            output.setsampwidth(2)
            output.setframerate(SAMPLE_RATE)
            output.writeframes((mix * 32767).astype("<i2").tobytes())
        destination = DESTINATION / (name + ".m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", str(source), str(destination)], check=True)
        print(f"{name}: {length / SAMPLE_RATE:.1f}s")


if __name__ == "__main__":
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for track in TRACKS:
        render(*track)
