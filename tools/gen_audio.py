"""Synthesise ALL of REALM's audio: ~45 sound effects and 3 music themes.

Run from the repo root (stdlib only, deterministic, takes about a minute):
    python tools/gen_audio.py
Every sample is computed here from sines, noise, Karplus-Strong plucks and
simple filters, so the audio is 100% original and there is nothing to license.
Output: game/assets/audio/sfx/*.wav and game/assets/audio/music/*.wav
(16-bit mono, 22.05 kHz). data/audio.json maps ids to these files.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio"
TAU = 2.0 * math.pi


# ----------------------------------------------------------------- basics

def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix_into(dst, src, at_seconds=0.0, gain=1.0):
    start = int(at_seconds * RATE)
    end = start + len(src)
    if end > len(dst):
        dst.extend([0.0] * (end - len(dst)))
    for i, v in enumerate(src):
        dst[start + i] += v * gain
    return dst


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def scale(samples, gain):
    return [s * gain for s in samples]


def normalize(samples, peak=0.85):
    m = max(1e-9, max(abs(s) for s in samples))
    return [s * peak / m for s in samples]


def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def envelope(n, attack=0.005, release_power=2.0, hold=0.0):
    """Fast attack, optional hold, power-curve decay to zero."""
    a = max(1, int(attack * RATE))
    h = int(hold * RATE)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        elif i < a + h:
            out.append(1.0)
        else:
            p = (i - a - h) / max(1, n - a - h)
            out.append((1.0 - p) ** release_power)
    return out


def apply_env(samples, env):
    return [s * e for s, e in zip(samples, env)]


def env_of(samples, attack=0.005, release_power=2.0):
    return apply_env(samples, envelope(len(samples), attack, release_power))


def lowpass(samples, cutoff):
    a = math.exp(-TAU * cutoff / RATE)
    y = 0.0
    out = []
    for x in samples:
        y = (1.0 - a) * x + a * y
        out.append(y)
    return out


def highpass(samples, cutoff):
    lp = lowpass(samples, cutoff)
    return [x - l for x, l in zip(samples, lp)]


def bandpass(samples, low, high):
    return lowpass(highpass(samples, low), high)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(RATE * seconds))]


def sweep_sine(f0, f1, seconds, harmonics=(1.0,), curve=1.0):
    """Sine (plus harmonics) whose pitch glides from f0 to f1."""
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        p = (i / max(1, n - 1)) ** curve
        f = f0 + (f1 - f0) * p
        phase += TAU * f / RATE
        v = 0.0
        for k, amp in enumerate(harmonics):
            v += amp * math.sin(phase * (k + 1))
        out.append(v)
    return out


def partials(freqs_amps, seconds, decay_power=3.0):
    """Inharmonic partials (bells, metal): each decays on its own."""
    n = int(RATE * seconds)
    out = [0.0] * n
    for f, amp, life in freqs_amps:
        ln = min(n, int(RATE * seconds * life))
        for i in range(ln):
            p = i / max(1, ln - 1)
            out[i] += amp * math.sin(TAU * f * i / RATE) * (1.0 - p) ** decay_power
    return out


def pluck(freq, seconds, rng, decay=0.996, bright=0.5):
    """Karplus-Strong plucked string (lute, harp, bow string)."""
    period = max(2, int(RATE / freq))
    buf = lowpass([rng.uniform(-1.0, 1.0) for _ in range(period)], 2000 + 6000 * bright)
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        j = i % period
        k = (i + 1) % period
        v = buf[j]
        out.append(v)
        buf[j] = decay * (0.5 * (v + buf[k]))
    return out


def saw(freq, seconds, vibrato=0.0):
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq * (1.0 + vibrato * math.sin(TAU * 5.0 * i / RATE))
        phase = (phase + f / RATE) % 1.0
        out.append(2.0 * phase - 1.0)
    return out


def flute(freq, seconds, rng):
    """Soft breathy wind voice: sine + 2nd harmonic, vibrato, breath noise."""
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    breath = lowpass([rng.uniform(-1, 1) for _ in range(n)], 1800)
    a = int(0.06 * RATE)
    r = int(0.12 * RATE)
    for i in range(n):
        vib = 1.0 + 0.004 * math.sin(TAU * 5.2 * i / RATE) * min(1.0, i / (0.3 * RATE))
        phase += TAU * freq * vib / RATE
        e = min(1.0, i / a) * min(1.0, (n - i) / r)
        out.append(e * (math.sin(phase) + 0.25 * math.sin(2 * phase) + 0.1 * breath[i]))
    return out


def brass(freq, seconds):
    """Filtered saw with a swelling attack: horns and fanfares."""
    s = lowpass(saw(freq, seconds, vibrato=0.003), freq * 4.0)
    n = len(s)
    a = int(0.04 * RATE)
    r = int(0.10 * RATE)
    return [v * min(1.0, i / a) * min(1.0, (n - i) / r) for i, v in enumerate(s)]


def reverb(samples, wet=0.25):
    """Tiny Schroeder-style room: three feedback combs."""
    out = list(samples) + [0.0] * int(0.4 * RATE)
    tail = [0.0] * len(out)
    for delay, fb in ((int(0.0297 * RATE), 0.55), (int(0.0371 * RATE), 0.5), (int(0.0411 * RATE), 0.45)):
        buf = [0.0] * len(out)
        for i in range(len(out)):
            y = out[i] + (fb * buf[i - delay] if i >= delay else 0.0)
            buf[i] = y
            tail[i] += y / 3.0
    return [d + wet * t for d, t in zip(out, tail)]


def write(folder, name, samples, peak=0.85):
    path = ROOT / folder / f"{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    data = normalize(samples, peak)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in data))
    print(f"wrote {folder}/{name}.wav  {len(samples) / RATE:.2f}s")


# ----------------------------------------------------------------- sound effects

def sfx_all():
    rng = random.Random(1209)

    def S(name, s, peak=0.85):
        write("sfx", name, s, peak)

    # --- UI
    S("ui_click", env_of(sweep_sine(1700, 1400, 0.035), 0.001, 3.0), 0.5)
    S("ui_open", concat(env_of(sweep_sine(660, 660, 0.06, (1, 0.3)), 0.003),
                        env_of(sweep_sine(990, 990, 0.09, (1, 0.3)), 0.003)), 0.55)
    S("ui_back", concat(env_of(sweep_sine(880, 880, 0.06, (1, 0.3)), 0.003),
                        env_of(sweep_sine(587, 587, 0.09, (1, 0.3)), 0.003)), 0.55)
    S("error", env_of(sweep_sine(220, 180, 0.18, (1, 0.5, 0.3)), 0.004, 1.2), 0.6)
    for k, (a, b) in enumerate(((784, 1175), (698, 1047))):
        S(f"select_{k + 1}", env_of(concat(pluck(a, 0.05, rng, 0.99, 0.8), pluck(b, 0.12, rng, 0.993, 0.8)), 0.001, 1.5), 0.55)
    for k, notes in enumerate(((523, 659, 784), (587, 740, 880))):
        s = silence(0.25)
        for i, f in enumerate(notes):
            mix_into(s, pluck(f, 0.16, rng, 0.994, 0.7), i * 0.045, 0.8)
        S(f"order_move_{k + 1}", s, 0.6)
    S("order_stop", env_of(concat(pluck(392, 0.07, rng, 0.99), pluck(294, 0.16, rng, 0.99)), 0.001, 1.4), 0.6)
    thud = env_of(lowpass(noise(0.12, rng), 400), 0.002, 3)
    S("place_building", mix_into(thud, env_of(sweep_sine(160, 90, 0.15), 0.002, 2), 0.0, 0.8), 0.7)

    # --- work
    for k in range(3):
        f = 170 + 25 * k
        s = env_of(lowpass(noise(0.09, rng), 900), 0.001, 4)
        mix_into(s, env_of(sweep_sine(f, f * 0.7, 0.12, (1, 0.4)), 0.001, 3), 0, 0.9)
        mix_into(s, pluck(f * 2.1, 0.14, rng, 0.97, 0.3), 0.003, 0.35)
        S(f"chop_{k + 1}", s, 0.7)
    for k in range(3):
        base = 1150 + 140 * k
        s = partials(((base, 1.0, 0.7), (base * 1.63, 0.6, 0.5), (base * 2.31, 0.4, 0.35), (base * 3.1, 0.25, 0.25)), 0.22, 4.0)
        mix_into(s, env_of(highpass(noise(0.02, rng), 2500), 0.0005, 2), 0, 0.8)
        S(f"mine_{k + 1}", s, 0.6)
    for k in range(3):
        f = 360 + 45 * k
        s = env_of(sweep_sine(f, f * 0.8, 0.09, (1, 0.6, 0.3)), 0.0008, 3.5)
        mix_into(s, env_of(bandpass(noise(0.03, rng), 600, 3000), 0.0005, 2), 0, 0.6)
        S(f"hammer_{k + 1}", s, 0.65)
    for k in range(2):
        n = noise(0.22, rng)
        trem = [0.6 + 0.4 * math.sin(TAU * (18 + 5 * k) * i / RATE) for i in range(len(n))]
        S(f"farm_{k + 1}", env_of(apply_env(bandpass(n, 900, 3500), trem), 0.03, 1.5), 0.45)
    for k in range(2):
        s = env_of(bandpass(noise(0.14, rng), 1200, 4500), 0.01, 2)
        mix_into(s, pluck(900 + 150 * k, 0.08, rng, 0.98, 0.9), 0.05, 0.3)
        S(f"forage_{k + 1}", s, 0.45)
    for k in range(2):
        s = partials(((2350 + 200 * k, 1.0, 0.6), (3500 + 250 * k, 0.7, 0.45)), 0.16, 3.0)
        mix_into(s, partials(((2700 + 200 * k, 0.9, 0.6), (4100, 0.5, 0.4)), 0.14, 3.0), 0.05, 0.8)
        S(f"deposit_{k + 1}", s, 0.5)

    # --- combat
    for k in range(3):
        s = env_of(highpass(noise(0.05, rng), 1800), 0.0005, 3)
        b = 2100 + 260 * k
        mix_into(s, partials(((b, 1.0, 0.8), (b * 1.48, 0.7, 0.6), (b * 2.07, 0.5, 0.45), (b * 0.53, 0.4, 0.5)), 0.2, 3.0), 0, 0.7)
        S(f"sword_{k + 1}", s, 0.6)
    for k in range(2):
        s = pluck(105 + 12 * k, 0.18, rng, 0.985, 0.4)
        mix_into(s, env_of(bandpass(noise(0.16, rng), 1500, 5000), 0.04, 2), 0.02, 0.45)
        S(f"bow_{k + 1}", s, 0.6)
    for k in range(2):
        s = env_of(lowpass(noise(0.06, rng), 1200), 0.0005, 3)
        mix_into(s, env_of(sweep_sine(320 + 40 * k, 200, 0.06), 0.0005, 3), 0, 0.8)
        S(f"arrow_hit_{k + 1}", s, 0.6)
    creak = env_of(bandpass(saw(70, 0.25), 200, 900), 0.08, 1.0)
    boom = env_of(sweep_sine(85, 45, 0.35, (1, 0.3)), 0.002, 2)
    S("siege_fire", mix_into(creak, concat(silence(0.18), boom), 0, 0.9), 0.75)
    crash = env_of(lowpass(noise(0.6, rng), 1400), 0.002, 2.5)
    mix_into(crash, env_of(sweep_sine(70, 38, 0.5, (1, 0.4)), 0.002, 2), 0, 1.0)
    S("siege_hit", crash, 0.8)
    for k in range(2):
        s = env_of(lowpass(noise(0.16, rng), 700 + 200 * k), 0.001, 3)
        mix_into(s, env_of(sweep_sine(120 + 20 * k, 80, 0.16), 0.001, 2.5), 0, 0.9)
        S(f"hit_building_{k + 1}", s, 0.7)
    for k in range(2):
        s = env_of(sweep_sine(300 - 40 * k, 120, 0.3, (1, 0.5, 0.25)), 0.01, 1.8)
        mix_into(s, env_of(lowpass(noise(0.12, rng), 500), 0.001, 3), 0.2, 0.9)
        S(f"death_{k + 1}", lowpass(s, 2500), 0.55)
    n = int(1.3 * RATE)
    grains = [0.0] * n
    for _ in range(70):
        at = rng.uniform(0, 1.0)
        g = env_of(lowpass(noise(0.08, rng), rng.uniform(300, 1500)), 0.001, 3)
        mix_into(grains, g, at, rng.uniform(0.3, 1.0) * (1.0 - at * 0.6))
    mix_into(grains, env_of(sweep_sine(60, 35, 0.9, (1, 0.5)), 0.005, 2), 0, 1.2)
    S("collapse", grains[:n], 0.8)
    heal = silence(0.6)
    for i, f in enumerate((1047, 1319, 1568)):
        mix_into(heal, partials(((f, 1.0, 1.0), (f * 2.0, 0.3, 0.6), (f * 3.01, 0.15, 0.4)), 0.45, 2.0), i * 0.07, 0.6)
    S("heal", heal, 0.5)

    # --- events
    horn = concat(brass(220, 0.28), brass(277, 0.28), brass(220, 0.42))
    mix_into(horn, scale(concat(brass(330, 0.28), brass(415, 0.28), brass(330, 0.42)), 0.6), 0)
    S("alert", reverb(horn), 0.75)
    s = silence(0.6)
    for i, f in enumerate((392, 494, 587, 784)):
        mix_into(s, pluck(f, 0.4, rng, 0.996, 0.7), i * 0.08)
    S("build_done", reverb(s), 0.65)
    s = concat(brass(330, 0.12), silence(0.03), brass(440, 0.25))
    mix_into(s, scale(concat(brass(262, 0.12), silence(0.03), brass(330, 0.25)), 0.5), 0)
    S("unit_ready", reverb(s), 0.6)
    s = silence(1.0)
    for i, f in enumerate((880, 1109, 1319, 1760)):
        mix_into(s, partials(((f, 1.0, 1.0), (f * 2.76, 0.35, 0.5), (f * 5.4, 0.12, 0.3)), 0.7, 2.5), i * 0.09, 0.6)
    S("research_done", reverb(s), 0.6)
    fan = silence(2.0)
    for i, m in enumerate((60, 64, 67)):
        mix_into(fan, brass(midi(m), 0.18), i * 0.16)
    for m in (60, 64, 67, 72):
        mix_into(fan, brass(midi(m), 1.2), 0.5, 0.6)
    S("era_up", reverb(fan, 0.3), 0.8)
    vic = silence(3.6)
    seq = ((67, 0.0, 0.2), (67, 0.22, 0.2), (67, 0.44, 0.2), (72, 0.66, 0.6), (71, 1.3, 0.25), (72, 1.58, 0.25), (76, 1.86, 1.4))
    for m, at, d in seq:
        mix_into(vic, brass(midi(m), d), at)
        mix_into(vic, brass(midi(m - 12), d), at, 0.5)
    for m in (60, 64, 67):
        mix_into(vic, brass(midi(m), 1.4), 1.86, 0.45)
    S("victory", reverb(vic, 0.35), 0.8)
    dft = silence(3.2)
    for i, m in enumerate((69, 67, 65, 64, 62, 57)):
        mix_into(dft, pluck(midi(m), 0.9, rng, 0.997, 0.4), i * 0.42)
    mix_into(dft, flute(midi(45), 2.6, rng), 0.3, 0.25)
    S("defeat", reverb(dft, 0.35), 0.7)


# ----------------------------------------------------------------- music

DORIAN = (0, 2, 3, 5, 7, 9, 10)
MIXOLYDIAN = (0, 2, 4, 5, 7, 9, 10)
AEOLIAN = (0, 2, 3, 5, 7, 8, 10)
RHYTHMS = ((2, 2, 2, 2), (3, 1, 2, 2), (4, 2, 2), (2, 2, 4), (1, 1, 2, 4), (6, 2), (2, 1, 1, 4), (8,))


def degree_to_midi(root, mode, degree):
    octave, idx = divmod(degree, 7)
    return root + 12 * octave + mode[idx]


def make_phrase(rng, chords, low, high, ending=None):
    """4 bars of melody as (degree, eighths) per bar, chord tones on downbeats."""
    bars = []
    deg = rng.randint(low + 2, high - 2)
    for chord in chords:
        rhythm = list(rng.choice(RHYTHMS))
        notes = []
        for k, length in enumerate(rhythm):
            if k == 0:
                tones = [chord + t + 7 * o for t in (0, 2, 4) for o in (-1, 0, 1, 2) if low <= chord + t + 7 * o <= high]
                deg = min(tones, key=lambda t: abs(t - deg)) if tones else deg
            else:
                deg = max(low, min(high, deg + rng.choice((-2, -1, -1, 1, 1, 2, 0))))
            notes.append((deg, length))
        bars.append(notes)
    if ending is not None:
        bars[-1] = [(bars[-1][0][0], 4), (ending, 4)]
    return bars


def render_theme(name, root, mode, bpm, progression, seed, style):
    rng = random.Random(seed)
    eighth = 60.0 / bpm / 2.0
    bars = len(progression)
    length = bars * 8 * eighth
    out = [0.0] * int(length * RATE)

    # Melody: phrases A B A C (C resolves to the tonic).
    groups = [progression[i:i + 4] for i in range(0, bars, 4)]
    a = make_phrase(rng, groups[0], 7, 14)
    b = make_phrase(rng, groups[1 % len(groups)], 8, 15)
    c = make_phrase(rng, groups[-1], 7, 14, ending=7)
    melody = (a + b + a + c)[:bars]

    for bar in range(bars):
        t0 = bar * 8 * eighth
        chord = progression[bar]
        # Bass / drone.
        if style == "battle":
            f = midi(degree_to_midi(root - 24, mode, chord))
            for e in range(8):
                mix_into(out, env_of(lowpass(saw(f, eighth * 0.9), 500), 0.005, 1.2), t0 + e * eighth, 0.22)
        else:
            mix_into(out, pluck(midi(degree_to_midi(root - 24, mode, chord)), 8 * eighth, rng, 0.998, 0.3), t0, 0.5)
            mix_into(out, pluck(midi(degree_to_midi(root - 12, mode, chord + 4)), 4 * eighth, rng, 0.997, 0.3), t0 + 4 * eighth, 0.25)
        # Arpeggio (lute / harp).
        pattern = (0, 2, 4, 7, 4, 2, 0, 2) if style != "battle" else (0, 4, 7, 4, 0, 4, 7, 4)
        for e, step in enumerate(pattern):
            if style == "menu" and e % 2 == 1:
                continue
            f = midi(degree_to_midi(root - 12, mode, chord + step))
            mix_into(out, pluck(f, 3 * eighth, rng, 0.995, 0.6), t0 + e * eighth, 0.22 if style != "battle" else 0.14)
        # Melody.
        at = t0
        for deg, ln in melody[bar]:
            f = midi(degree_to_midi(root, mode, deg))
            dur = ln * eighth
            if style == "battle":
                voice, gain = brass(f, dur * 0.95), 0.32
            elif style == "menu":
                voice, gain = pluck(f, dur + 0.5, rng, 0.998, 0.8), 0.45
            else:
                voice, gain = flute(f, dur * 0.97, rng), 0.3
            mix_into(out, voice, at, gain)
            at += dur
        # Percussion.
        if style == "battle":
            for e in range(8):
                if e in (0, 3, 4, 6):
                    mix_into(out, env_of(sweep_sine(110, 45, 0.25), 0.001, 2.5), t0 + e * eighth, 0.55)
                if e in (2, 6):
                    mix_into(out, env_of(bandpass(noise(0.14, rng), 900, 6000), 0.001, 3), t0 + e * eighth, 0.28)
        elif style == "peace":
            for e in (0, 3, 6):
                mix_into(out, env_of(sweep_sine(150, 70, 0.18), 0.002, 3), t0 + e * eighth, 0.18)

    # Seamless loop: fold the tail that rang past the end back onto the start.
    total = int(length * RATE)
    wet = reverb(out, 0.22)
    loop = wet[:total]
    for i, v in enumerate(wet[total:]):
        if i < total:
            loop[i] += v
    write("music", name, loop, 0.8)


def music_all():
    # Menu: slow harp in D dorian. Peace: lute + flute in G mixolydian.
    # Battle: driving drums, low strings and horns in A minor.
    render_theme("menu", 62, DORIAN, 72, [0, 3, 0, 4, 5, 3, 4, 0, 0, 3, 0, 4], 11, "menu")
    render_theme("peace", 67, MIXOLYDIAN, 88, [0, 6, 3, 0, 0, 6, 4, 0, 3, 0, 6, 4, 0, 6, 3, 0], 23, "peace")
    render_theme("battle", 57, AEOLIAN, 132, [0, 0, 5, 6, 0, 0, 3, 4, 5, 6, 0, 0, 5, 3, 4, 0], 37, "battle")


if __name__ == "__main__":
    sfx_all()
    music_all()
