#!/usr/bin/env python3
"""Synthesize the game's sound effects as 8-bit mono WAV files."""
import math, os, random, struct, sys, wave

RATE = 22050
random.seed(7)


def square(f, t):
    return 1.0 if math.sin(2 * math.pi * f * t) >= 0 else -1.0


def render(path, dur, fn, vol=0.5):
    n = int(RATE * dur)
    frames = bytearray()
    for i in range(n):
        t = i / RATE
        env = min(1.0, (n - i) / (RATE * 0.03))  # short fade-out, no click
        v = max(-1.0, min(1.0, fn(t, t / dur))) * env * vol
        frames.append(int(128 + 127 * v))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


def seq(notes, step):
    """Notes in Hz, one per `step` seconds, square wave."""
    def fn(t, p):
        k = min(int(t / step), len(notes) - 1)
        return square(notes[k], t) * (1 - (t % step) / step * 0.5)
    return fn


def main(out):
    os.makedirs(out, exist_ok=True)
    P = lambda n: os.path.join(out, n + ".wav")
    render(P("shoot"), 0.14, lambda t, p: square(1000 - 800 * p, t), 0.35)
    render(P("kill"), 0.22,
           lambda t, p: (square(400 - 300 * p, t) * 0.6
                         + random.uniform(-1, 1) * 0.5) * (1 - p), 0.55)
    render(P("hit"), 0.08, lambda t, p: random.uniform(-1, 1) * (1 - p), 0.35)
    render(P("ufohit"), 0.45, seq([523, 659, 784, 1047, 1319], 0.09), 0.4)
    render(P("dead"), 0.9,
           lambda t, p: (random.uniform(-1, 1) * 0.7
                         + square(180 - 140 * p, t) * 0.5) * (1 - p) ** 1.5,
           0.7)
    for i, f in enumerate((55, 49, 44, 41), 1):
        render(P("march%d" % i), 0.09,
               lambda t, p, f=f: square(f, t) * (1 - p), 0.6)
    render(P("ufo"), 0.25,
           lambda t, p: square(700 + 250 * math.sin(2 * math.pi * 14 * t), t),
           0.2)
    render(P("wave"), 0.5, seq([392, 523, 659, 784], 0.12), 0.4)
    render(P("gameover"), 1.1, seq([392, 349, 330, 262, 196], 0.22), 0.45)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "sounds")
