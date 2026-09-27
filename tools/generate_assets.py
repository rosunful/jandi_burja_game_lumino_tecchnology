#!/usr/bin/env python3
"""Generates the bundled binary assets that ship with Janda Burja.

Everything here is synthesised from scratch with the Python standard library
plus Pillow, so the build has no network dependency and no licensing questions.
Re-run after tweaking to regenerate assets/ in place:

    python3 tools/generate_assets.py

Sound effects are deliberately short and mono so the whole audio set costs well
under a megabyte in the APK.
"""

import math
import os
import random
import struct
import wave

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FELT_DIR = os.path.join(ROOT, "assets", "felt")
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")

SAMPLE_RATE = 22050
RNG = random.Random(20260927)  # fixed seed: assets are reproducible


# --------------------------------------------------------------------- felt
def generate_felt(path, size=1024):
    """A dark green casino felt: low-frequency mottling plus fine fibre noise.

    Stretched to fill the screen rather than tiled, so it needs no seam
    wrapping. Smoothing keeps it soft when upscaled on large displays.
    """
    base = (18, 74, 48)

    # Coarse mottling, upscaled with bicubic to get broad cloudy variation.
    coarse = Image.new("L", (size // 16, size // 16))
    coarse.putdata([RNG.randint(0, 255) for _ in range(coarse.width * coarse.height)])
    coarse = coarse.resize((size, size), Image.BICUBIC)
    coarse = coarse.filter(ImageFilter.GaussianBlur(12))

    # Fine fibre speckle.
    fine = Image.new("L", (size, size))
    fine.putdata([RNG.randint(0, 255) for _ in range(size * size)])
    fine = fine.filter(ImageFilter.GaussianBlur(0.4))

    r, g, b = base
    pixels = []
    coarse_px = coarse.load()
    fine_px = fine.load()
    for y in range(size):
        for x in range(size):
            c = (coarse_px[x, y] - 128) / 128.0 * 26.0
            f = (fine_px[x, y] - 128) / 128.0 * 9.0
            d = c + f
            pixels.append(
                (
                    max(0, min(255, int(r + d * 0.55))),
                    max(0, min(255, int(g + d))),
                    max(0, min(255, int(b + d * 0.7))),
                )
            )

    felt = Image.new("RGB", (size, size))
    felt.putdata(pixels)
    felt.save(path, optimize=True)
    print(f"  felt      {size}x{size} -> {os.path.relpath(path, ROOT)}")


# -------------------------------------------------------------------- audio
def _write_wav(path, samples):
    frames = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(frames)
    print(
        f"  {os.path.splitext(os.path.basename(path))[0]:10} "
        f"{len(samples) / SAMPLE_RATE:4.2f}s "
        f"{os.path.getsize(path) / 1024:6.1f} KB"
    )


def _noise_burst(duration, decay, cutoff=0.5):
    """A decaying noise burst, low-passed so it reads as a click not a hiss."""
    n = int(SAMPLE_RATE * duration)
    raw = [RNG.uniform(-1, 1) for _ in range(n)]
    # One-pole low-pass, strength from cutoff (0 = muffled, 1 = bright).
    a = max(0.02, min(0.99, cutoff))
    out, prev = [], 0.0
    for s in raw:
        prev = prev + a * (s - prev)
        out.append(prev * math.exp(-decay * len(out) / n))
    return out


def _tone(freq, duration, decay=4.0, harmonics=(1.0, 0.35, 0.12)):
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-decay * t / duration)
        s = sum(
            amp * math.sin(2 * math.pi * freq * (k + 1) * t)
            for k, amp in enumerate(harmonics)
        )
        out.append(s * env)
    return out


def _mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    peak = max((abs(s) for s in out), default=1.0) or 1.0
    return [s / peak * 0.85 for s in out]


def _sequence(notes, note_len, decay=5.0):
    """Concatenate tones, each fading in and out so notes do not click."""
    out = []
    for freq in notes:
        seg = _tone(freq, note_len, decay=decay)
        fade = max(1, int(len(seg) * 0.12))
        for i in range(fade):
            seg[i] *= i / fade
            seg[-1 - i] *= i / fade
        out.extend(seg)
    return out


def _silence(duration):
    return [0.0] * int(SAMPLE_RATE * duration)


N = {
    "C5": 523.25,
    "D5": 587.33,
    "E5": 659.25,
    "G5": 783.99,
    "A5": 880.00,
    "C6": 1046.50,
    "G4": 392.00,
    "E4": 329.63,
    "C4": 261.63,
}


def generate_audio():
    # Chip landing on felt: tight, woody, very short.
    _write_wav(
        os.path.join(AUDIO_DIR, "chip_place.wav"),
        _mix(_noise_burst(0.07, decay=9.0, cutoff=0.28), _tone(520, 0.05, decay=14)),
    )

    # Dice rattling in a cup before the throw: scattered clicks.
    rattle = []
    for _ in range(14):
        rattle.extend(_silence(RNG.uniform(0.012, 0.045)))
        rattle.extend(_noise_burst(0.05, decay=11.0, cutoff=RNG.uniform(0.25, 0.5)))
    rattle.extend(_silence(0.05))
    _write_wav(os.path.join(AUDIO_DIR, "dice_rattle.wav"), _mix(rattle))

    # The throw itself: a swelling tumble that decays as the dice settle.
    n = int(SAMPLE_RATE * 1.1)
    roll, prev = [], 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        swell = math.sin(math.pi * min(1.0, t / 1.1)) ** 1.5
        prev = prev + 0.22 * (RNG.uniform(-1, 1) - prev)
        roll.append(prev * swell)
    for _ in range(5):
        roll.extend(_silence(RNG.uniform(0.02, 0.05)))
        roll.extend(_noise_burst(0.06, decay=10.0, cutoff=0.3))
    _write_wav(os.path.join(AUDIO_DIR, "dice_roll.wav"), _mix(roll))

    # Win: bright ascending major arpeggio.
    _write_wav(
        os.path.join(AUDIO_DIR, "win.wav"),
        _sequence([N["C5"], N["E5"], N["G5"], N["C6"]], 0.11),
    )

    # Big win: longer flourish, used when a multi-symbol round pays.
    _write_wav(
        os.path.join(AUDIO_DIR, "win_big.wav"),
        _sequence([N["C5"], N["E5"], N["G5"], N["C6"], N["E5"], N["G5"], N["C6"]], 0.10),
    )

    # Lose: soft descending two notes, never harsh or punishing.
    _write_wav(
        os.path.join(AUDIO_DIR, "lose.wav"),
        _sequence([N["G4"], N["E4"]], 0.17, decay=4.0),
    )

    # UI tick for chip selection.
    _write_wav(
        os.path.join(AUDIO_DIR, "select.wav"),
        _mix(_tone(880, 0.04, decay=16), _noise_burst(0.03, decay=18, cutoff=0.4)),
    )


def main():
    os.makedirs(FELT_DIR, exist_ok=True)
    os.makedirs(AUDIO_DIR, exist_ok=True)
    print("Generating assets:")
    generate_felt(os.path.join(FELT_DIR, "felt.png"))
    generate_audio()
    print("Done.")


if __name__ == "__main__":
    main()
