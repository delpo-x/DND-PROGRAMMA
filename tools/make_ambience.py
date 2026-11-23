"""Builds the looping ambience sounds of Dnd The Game (web/amb/*.wav).

Everything is synthesized here from noise, filters and a few short samples
rendered with earshot's sound bank (tools/amb_samples: drips, a wooden knock,
a glass clink). Each file is a mono 22050 Hz loop whose end flows into its
start, so the game can repeat it with no gap.

    python tools/make_ambience.py

Needs numpy and scipy. The output is deterministic (fixed seeds).
"""

import os

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
LEN = 24.0  # seconds of each loop
FADE = 2.0  # seconds blended from the end into the start
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "web", "amb")
SAMPLES = os.path.join(HERE, "amb_samples")


# ------------------------------------------------------------------ helpers
def n_samples(sec=LEN + FADE):
    return int(sec * SR)


def noise(rng, n):
    return rng.standard_normal(n)


def brown(rng, n):
    x = np.cumsum(rng.standard_normal(n))
    x = signal.lfilter([1, -1], [1, -0.995], x)  # keep it from drifting away
    return x / (np.abs(x).max() + 1e-9)


def band(x, lo, hi, order=2):
    nyq = SR / 2
    if lo <= 0:
        b, a = signal.butter(order, hi / nyq, "low")
    elif hi >= nyq:
        b, a = signal.butter(order, lo / nyq, "high")
    else:
        b, a = signal.butter(order, [lo / nyq, hi / nyq], "band")
    return signal.lfilter(b, a, x)


def lfo(rng, n, rate, depth=1.0, base=0.0):
    """Slow random movement between base and base + depth."""
    pts = int(n / SR * rate) + 4
    v = rng.random(pts)
    x = np.interp(np.linspace(0, pts - 3, n), np.arange(pts), v)
    x = (x - x.min()) / (x.max() - x.min() + 1e-9)
    return base + depth * x


def sample(name):
    sr, x = wavfile.read(os.path.join(SAMPLES, name))
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x /= np.abs(x).max() + 1e-9
    return signal.resample_poly(x, SR, sr)


def place(out, snd, at, gain, rate=1.0):
    if rate != 1.0:
        snd = signal.resample(snd, max(8, int(len(snd) / rate)))
    i = int(at * SR)
    j = min(len(out), i + len(snd))
    if i < len(out):
        out[i:j] += snd[: j - i] * gain


def reverb(x, sec, wet, rng, bright=4000):
    ir_n = int(sec * SR)
    t = np.arange(ir_n) / SR
    ir = rng.standard_normal(ir_n) * np.exp(-6.9 * t / sec)
    ir = band(ir, 0, bright, 1)
    ir /= np.sqrt((ir ** 2).sum())
    return x + wet * signal.fftconvolve(x, ir)[: len(x)]


def events(rng, rate, length=LEN + FADE):
    """Random times, about `rate` per second."""
    t, out = 0.0, []
    while True:
        t += rng.exponential(1.0 / rate)
        if t >= length - 0.5:
            return out
        out.append(t)


def loop(x):
    """Blends the last FADE seconds into the first ones: a seamless loop."""
    n, f = n_samples(LEN), n_samples(FADE)
    y = x[:n].copy()
    w = np.sin(np.linspace(0, np.pi / 2, f)) ** 2
    y[:f] = x[:f] * w + x[n:n + f] * (1 - w)
    return y


def finish(name, x, rms_db=-27.0):
    y = loop(x)
    y -= y.mean()
    y *= 10 ** (rms_db / 20) / (np.sqrt((y ** 2).mean()) + 1e-12)
    if np.abs(y).max() > 0.7:  # soft limit the loudest events
        y = np.tanh(y / 0.7) * 0.7
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (y * 32767).astype(np.int16))
    print("%-10s rms %.1f dB  peak %.2f" % (name, 20 * np.log10(np.sqrt((y ** 2).mean())), np.abs(y).max()))


# ------------------------------------------------------------------ pieces
def wind(rng, n, strength=1.0):
    a = band(noise(rng, n), 180, 700) * lfo(rng, n, 0.12, 0.8, 0.2)
    b = band(noise(rng, n), 600, 1800) * lfo(rng, n, 0.2, 0.6, 0.1) * 0.35
    return (a + b) * strength


def birds(rng, n, rate):
    out = np.zeros(n)
    for t in events(rng, rate):
        # a phrase of two to five quick chirps
        f0 = rng.uniform(2300, 4200)
        gain = rng.uniform(0.05, 0.18)
        for c in range(rng.integers(2, 6)):
            d = rng.uniform(0.05, 0.12)
            tt = np.arange(int(d * SR)) / SR
            sweep = f0 * (1 + rng.uniform(-0.25, 0.35) * tt / d)
            ph = 2 * np.pi * np.cumsum(sweep) / SR
            env = np.sin(np.pi * tt / d) ** 2
            place(out, np.sin(ph + 0.6 * np.sin(2 * np.pi * 38 * tt)) * env, t + c * rng.uniform(0.09, 0.16), gain)
    return out


def crickets(rng, n):
    out = np.zeros(n)
    for _ in range(3):
        f = rng.uniform(4200, 5200)
        period = rng.uniform(0.6, 1.1)
        gain = rng.uniform(0.03, 0.06)
        tt = np.arange(int(0.18 * SR)) / SR
        chirp = np.sin(2 * np.pi * f * tt) * (np.sin(2 * np.pi * 30 * tt) > 0) * np.sin(np.pi * tt / 0.18)
        t = rng.uniform(0, period)
        while t < LEN + FADE - 0.3:
            place(out, chirp, t, gain * rng.uniform(0.7, 1.0))
            t += period * rng.uniform(0.9, 1.1)
    return out


def drips(rng, n, rate, far=False, tonal=True):
    snds = [sample("drip_drop.wav"), sample("drip_tiny.wav")]
    if tonal:
        snds.append(sample("drip_plink.wav"))
    out = np.zeros(n)
    for t in events(rng, rate):
        s = snds[rng.integers(0, len(snds))]
        place(out, s, t, rng.uniform(0.08, 0.25) * (0.5 if far else 1.0), rng.uniform(0.85, 1.2))
    return out


def plops(rng, n, rate):
    """Water drops falling into a puddle: a short sine that sweeps up fast,
    with a tiny splash. Less bell-like than the sampled drips."""
    out = np.zeros(n)
    for t in events(rng, rate):
        d = rng.uniform(0.03, 0.06)
        m = int(d * SR)
        tt = np.arange(m) / SR
        f = rng.uniform(350, 700) * np.exp(tt / d * rng.uniform(0.8, 1.4))
        tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / d * 5)
        splash = band(noise(rng, m), 1500, 6000) * np.exp(-tt / d * 12) * 0.3
        place(out, tone + splash, t, rng.uniform(0.08, 0.25))
    return out


def crackle(rng, n, rate):
    out = np.zeros(n)
    for t in events(rng, rate):
        m = int(rng.uniform(0.004, 0.025) * SR)
        pop = band(noise(rng, m), 900, 7000) * np.exp(-np.linspace(0, 6, m))
        place(out, pop, t, rng.uniform(0.05, 0.4))
    return out


VOWELS = [(800, 1200), (500, 1800), (300, 2300), (500, 900), (320, 800)]  # a e i o u


def murmur(rng, n, voices):
    """Distant crowd talk. Many voices overlap, so it is mostly speech-shaped
    breathy noise pulsing at syllable rate, with a few voiced, jittery voices
    on top (a steady pitch would read as a brass instrument)."""
    out = np.zeros(n)
    for _ in range(voices):
        env = np.zeros(n)
        voiced = np.zeros(n)
        f0 = rng.uniform(95, 210)
        t = rng.uniform(0, 2)
        while t < LEN + FADE - 0.4:
            for _w in range(rng.integers(4, 14)):  # a sentence
                d = rng.uniform(0.1, 0.24)
                m = int(d * SR)
                tt = np.arange(m) / SR
                shape = np.sin(np.pi * tt / d) ** 2
                place(env, shape, t, rng.uniform(0.5, 1.0))
                jitter = np.cumsum(rng.normal(0, 0.004, m))
                pitch = f0 * (1 + rng.uniform(-0.15, 0.15) + jitter)
                buzz = signal.sawtooth(2 * np.pi * np.cumsum(pitch) / SR)
                f1, f2 = VOWELS[rng.integers(0, len(VOWELS))]
                syl = band(buzz, f1 * 0.8, f1 * 1.25) + 0.4 * band(buzz, f2 * 0.85, f2 * 1.15)
                place(voiced, syl * shape, t, 1.0)
                t += d * rng.uniform(0.9, 1.3)
            t += rng.uniform(0.6, 3.0)  # pause
        breath = band(noise(rng, n), 250, 3200) * env
        out += (breath * 1.2 + voiced * 0.25) * rng.uniform(0.4, 1.0)
    return band(out, 0, 2600, 2)


# ------------------------------------------------------------------ places
def grotta(rng):
    n = n_samples()
    x = brown(rng, n) * 0.18 + wind(rng, n, 0.12)
    d = plops(rng, n, 0.9) * 0.9
    return reverb(x + d, 2.5, 0.6, rng, 3000)


def cripta(rng):
    n = n_samples()
    t = np.arange(n) / SR
    drone = (np.sin(2 * np.pi * 55 * t) + 0.6 * np.sin(2 * np.pi * 82.6 * t) + 0.3 * np.sin(2 * np.pi * 110.4 * t))
    x = drone * lfo(rng, n, 0.08, 0.6, 0.4) * 0.08 + wind(rng, n, 0.25) + drips(rng, n, 0.25, far=True)
    return reverb(x, 2.6, 1.1, rng, 1800)


def bosco(rng):
    n = n_samples()
    leaves = band(noise(rng, n), 2000, 7000) * lfo(rng, n, 0.4, 0.5, 0.02) ** 2 * 0.25
    return reverb(wind(rng, n, 0.22) + leaves + birds(rng, n, 0.6) * 1.4, 0.6, 0.25, rng, 6000)


def notte(rng):
    n = n_samples()
    x = wind(rng, n, 0.3) + crickets(rng, n)
    t0 = rng.uniform(6, 14)  # an owl, once per loop
    for i, (f, d) in enumerate([(380, 0.35), (360, 0.6)]):
        tt = np.arange(int(d * SR)) / SR
        hoot = np.sin(2 * np.pi * f * tt * (1 - 0.04 * tt / d)) * np.sin(np.pi * tt / d) ** 1.5
        place(x, hoot, t0 + i * 0.55, 0.12)
    return reverb(x, 1.2, 0.35, rng, 5000)


def vento(rng):
    n = n_samples()
    gust = band(noise(rng, n), 300, 1200) * lfo(rng, n, 0.3, 1.0) ** 2 * 0.6
    whistle = band(noise(rng, n), 1100, 1400, 4) * lfo(rng, n, 0.1, 1.0) ** 3 * 2.0
    return wind(rng, n, 1.2) + gust + whistle


def pioggia(rng):
    n = n_samples()
    hiss = band(noise(rng, n), 2500, 9000) * 0.12 * lfo(rng, n, 0.15, 0.3, 0.7)
    body = band(noise(rng, n), 300, 1500) * 0.08
    drops = np.zeros(n)
    for t in events(rng, 260):
        m = int(rng.uniform(0.002, 0.012) * SR)
        lo = rng.uniform(700, 4500)
        d = band(noise(rng, m), lo, min(10000, lo * 2.5)) * np.exp(-np.linspace(0, 7, m))
        place(drops, d, t, rng.uniform(0.02, 0.3) ** 1.5)
    gutter = drips(rng, n, 0.6) * 0.4  # water running off a roof
    return hiss + body + drops * 1.6 + gutter + brown(rng, n) * 0.08


def mare(rng):
    n = n_samples()
    t = np.arange(n) / SR
    period = LEN / 3  # three waves per loop, so the loop stays seamless
    swell = (0.5 - 0.5 * np.cos(2 * np.pi * t / period)) ** 2
    wash = band(noise(rng, n), 200, 2500) * swell
    foam = band(noise(rng, n), 2500, 8000) * np.roll(swell, int(0.6 * SR)) ** 3 * 0.5
    return wash + foam + brown(rng, n) * 0.12


def locanda(rng):
    n = n_samples()
    knock = sample("knock_wood.wav")
    clink = sample("clink.wav")
    talk = murmur(rng, n, 16)
    talk /= np.abs(talk).max() + 1e-9
    x = talk * 0.6 + crackle(rng, n, 3) * 0.12 + brown(rng, n) * 0.04
    for t in events(rng, 0.12):
        place(x, knock, t, rng.uniform(0.06, 0.14), rng.uniform(0.85, 1.1))
    for t in events(rng, 0.12):
        place(x, clink, t, rng.uniform(0.03, 0.07), rng.uniform(0.9, 1.15))
    return reverb(x, 0.9, 0.5, rng, 4000)


def fuoco(rng):
    n = n_samples()
    roar = band(brown(rng, n), 60, 400) * lfo(rng, n, 0.5, 0.4, 0.6) * 0.6
    hiss = band(noise(rng, n), 1500, 6000) * lfo(rng, n, 0.7, 0.5, 0.5) * 0.04
    return roar + crackle(rng, n, 14) * 1.2 + hiss + wind(rng, n, 0.1)


PLACES = {
    "grotta": grotta, "cripta": cripta, "bosco": bosco, "notte": notte, "vento": vento,
    "pioggia": pioggia, "mare": mare, "locanda": locanda, "fuoco": fuoco,
}

if __name__ == "__main__":
    for i, (name, fn) in enumerate(PLACES.items()):
        finish(name, fn(np.random.default_rng(1000 + i)))
