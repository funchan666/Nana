# Nana room music

The six files in `assets/room-music` are original, procedurally composed
instrumental loops. They contain synthesized keys, pads, bass and percussion;
no downloaded recordings, external samples, voices or lyrics are used.

Recreate them on macOS with `python3 scripts/generate_room_music.py` (NumPy and
the system `afconvert` utility are required). Outputs are stereo AAC at 96 kbps.
The deterministic generator preserves the file names used by the app catalog.

| File | Tempo | Approximate loop length |
| --- | --- | --- |
| moonlit-keys.m4a | 72 BPM | 26.7 seconds |
| slow-sunday.m4a | 80 BPM | 24.0 seconds |
| city-lights.m4a | 90 BPM | 21.3 seconds |
| quiet-tides.m4a | 68 BPM | 28.2 seconds |
| little-sparks.m4a | 96 BPM | 20.0 seconds |
| after-hours.m4a | 76 BPM | 25.3 seconds |

Playback is local to the device. This does not distribute audio to other room
members; a future room transport would need a separate synchronized music path.
The tracks are free and never write to the wallet. Backgrounding, interruptions
and headphone disconnection pause playback; exiting or changing rooms clears it.
