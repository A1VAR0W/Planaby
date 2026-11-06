"""Genera los sonidos de aviso de Planaby (originales, sintetizados aquí; sin muestras de terceros).

Uso: python tools/make_sounds.py  →  escribe App/Sounds/*.wav (mono, 44,1 kHz, 16 bits, < 2 s).

Tres juegos, cada uno con dos avisos:
- «break»: empieza el descanso (dos notas que bajan, cierran).
- «focus»: vuelta a concentrarse (dos notas que suben, abren).
"""
import math
import os
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'App', 'Sounds')


def note(freq, start, length, partials, decay, attack=0.004):
    """Una nota como suma de parciales (múltiplo de la frecuencia, amplitud) con caída exponencial."""
    samples = []
    for i in range(int(length * RATE)):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t * decay)
        value = sum(amp * math.sin(2 * math.pi * freq * ratio * t) for ratio, amp in partials)
        samples.append(value * env)
    return start, samples


def render(notes, total, volume=0.32):
    mix = [0.0] * int(total * RATE)
    for start, samples in notes:
        offset = int(start * RATE)
        for i, value in enumerate(samples):
            if offset + i < len(mix):
                mix[offset + i] += value
    peak = max(1e-9, max(abs(v) for v in mix))
    # Fundido final para que no haga clic.
    fade = int(0.05 * RATE)
    for i in range(fade):
        mix[-1 - i] *= i / fade
    return [v / peak * volume for v in mix]


def save(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in samples))
    print(path, f'{len(samples) / RATE:.2f} s')


# Campana suave: parciales armónicos con algo de octava, caída lenta.
BELL = [(1, 1.0), (2, 0.35), (3, 0.12), (4.2, 0.05)]
# Madera: casi solo fundamental y un parcial alto que muere enseguida (marimba).
WOOD = [(1, 1.0), (4, 0.25), (10, 0.04)]
# Cristal: parciales inarmónicos, brillo.
GLASS = [(1, 1.0), (2.76, 0.3), (5.4, 0.12), (8.93, 0.05)]

C5, D5, E5, G5, A4, C6, E6, G4 = 523.25, 587.33, 659.25, 783.99, 440.0, 1046.5, 1318.5, 392.0

sets = {
    'soft': (BELL, 3.2, [(E5, 0.0), (C5, 0.28)], [(C5, 0.0), (G5, 0.24)], 1.6),
    'wood': (WOOD, 9.0, [(G5, 0.0), (D5, 0.16)], [(D5, 0.0), (G5, 0.14)], 0.9),
    'glass': (GLASS, 4.0, [(E6, 0.0), (C6, 0.22)], [(C6, 0.0), (E6, 0.2)], 1.4),
}

for name, (partials, decay, down, up, total) in sets.items():
    for kind, melody in (('break', down), ('focus', up)):
        notes = [note(freq, start, total - start, partials, decay) for freq, start in melody]
        save(f'planaby-{name}-{kind}.wav', render(notes, total))
