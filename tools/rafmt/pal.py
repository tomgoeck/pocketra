

def load_palette(raw: bytes) -> list[tuple[int, int, int]]:
    if len(raw) < 768:
        raise ValueError("Palette zu kurz")
    return [
        (raw[i] << 2, raw[i + 1] << 2, raw[i + 2] << 2)
        for i in range(0, 768, 3)
    ]
