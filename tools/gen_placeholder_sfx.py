"""Generate original placeholder SFX as 16-bit mono WAV files (stdlib only).

Run from the repo root:
    python tools/gen_placeholder_sfx.py
Every sound is synthesised here from sine waves and envelopes, so there is
no third-party audio and nothing to license. Real audio replaces these in F9.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "placeholder" / "sfx"


def tone(freqs, seconds, volume=0.5, attack=0.005, decay_power=2.0, sweep=0.0):
    """Sum of sines with a fast attack and a power-curve decay. sweep shifts pitch over time."""
    n = int(RATE * seconds)
    samples = []
    for i in range(n):
        t = i / RATE
        progress = i / max(1, n - 1)
        env = min(1.0, t / attack) * (1.0 - progress) ** decay_power
        value = 0.0
        for f in freqs:
            freq = f * (1.0 + sweep * progress)
            value += math.sin(2.0 * math.pi * freq * t)
        samples.append(volume * env * value / len(freqs))
    return samples


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        wav.writeframes(frames)
    print("wrote", path, len(samples), "samples")


def main():
    # Short bright blip when units are selected.
    write("select", tone([880, 1320], 0.08, volume=0.45, decay_power=1.5))
    # Two rising notes to confirm a move order.
    write("order_move", tone([523, 784], 0.07, volume=0.5) + tone([659, 988], 0.10, volume=0.5))
    # Low falling note for stop / hold.
    write("order_stop", tone([392, 294], 0.14, volume=0.5, sweep=-0.25))
    # Very short tick for UI buttons.
    write("ui_click", tone([1500], 0.03, volume=0.35, decay_power=3.0))


if __name__ == "__main__":
    main()
