"""Generates placeholder PNG assets for Britannia Factory."""
import zlib
import struct


def make_png(width: int, height: int, pixels: list) -> bytes:
    """Encode a list of (r, g, b) tuples into a minimal valid PNG."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))

    raw = b""
    for row in range(height):
        raw += b"\x00"  # filter type: None
        for col in range(width):
            r, g, b = pixels[row * width + col]
            raw += bytes([r, g, b])

    idat = chunk(b"IDAT", zlib.compress(raw, 9))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def make_png_rgba(width: int, height: int, pixels: list) -> bytes:
    """Encode a list of (r, g, b, a) tuples into a minimal valid RGBA PNG."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))

    raw = b""
    for row in range(height):
        raw += b"\x00"  # filter type: None
        for col in range(width):
            r, g, b, a = pixels[row * width + col]
            raw += bytes([r, g, b, a])

    idat = chunk(b"IDAT", zlib.compress(raw, 9))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def point_in_triangle(px, py, ax, ay, bx, by, cx, cy) -> bool:
    def sign(p1x, p1y, p2x, p2y, p3x, p3y):
        return (p1x - p3x) * (p2y - p3y) - (p2x - p3x) * (p1y - p3y)
    d1 = sign(px, py, ax, ay, bx, by)
    d2 = sign(px, py, bx, by, cx, cy)
    d3 = sign(px, py, cx, cy, ax, ay)
    has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)


# wilderness.png: 64x32 — two 32x32 tiles side by side
# Left tile (atlas 0,0): grass green
# Right tile (atlas 1,0): wall gray
GRASS = (100, 180, 60)
WALL = (90, 90, 90)

wilderness_pixels = [
    GRASS if col < 32 else WALL
    for row in range(32)
    for col in range(64)
]

with open("assets/tilesets/wilderness.png", "wb") as f:
    f.write(make_png(64, 32, wilderness_pixels))
print("assets/tilesets/wilderness.png  OK")

# player.png: 32x32 solid red square
PLAYER = (220, 80, 80)

player_pixels = [PLAYER] * (32 * 32)

with open("assets/sprites/player.png", "wb") as f:
    f.write(make_png(32, 32, player_pixels))
print("assets/sprites/player.png  OK")

# npc_innkeeper.png: 32x32 solid blue square
NPC = (60, 120, 220)

npc_pixels = [NPC] * (32 * 32)

with open("assets/sprites/npc_innkeeper.png", "wb") as f:
    f.write(make_png(32, 32, npc_pixels))
print("assets/sprites/npc_innkeeper.png  OK")

# item.png: 32x32 gold triangle (pointing up) on transparent background
ITEM_COLOR = (220, 180, 40, 255)
TRANSPARENT = (0, 0, 0, 0)

item_pixels = []
for row in range(32):
    for col in range(32):
        if point_in_triangle(col, row, 16, 3, 3, 29, 29, 29):
            item_pixels.append(ITEM_COLOR)
        else:
            item_pixels.append(TRANSPARENT)

with open("assets/sprites/item.png", "wb") as f:
    f.write(make_png_rgba(32, 32, item_pixels))
print("assets/sprites/item.png  OK")

# object_carriable.png: 32x32 gold triangle on transparent background
CARRIABLE_COLOR = (220, 180, 40, 255)

object_carriable_pixels = [
    CARRIABLE_COLOR if point_in_triangle(col, row, 16, 3, 3, 29, 29, 29) else TRANSPARENT
    for row in range(32)
    for col in range(32)
]

with open("assets/sprites/object_carriable.png", "wb") as f:
    f.write(make_png_rgba(32, 32, object_carriable_pixels))
print("assets/sprites/object_carriable.png  OK")

# object_noncarriable.png: 32x32 steel-blue triangle on transparent background
NONCARRIABLE_COLOR = (80, 130, 200, 255)

object_noncarriable_pixels = [
    NONCARRIABLE_COLOR if point_in_triangle(col, row, 16, 3, 3, 29, 29, 29) else TRANSPARENT
    for row in range(32)
    for col in range(32)
]

with open("assets/sprites/object_noncarriable.png", "wb") as f:
    f.write(make_png_rgba(32, 32, object_noncarriable_pixels))
print("assets/sprites/object_noncarriable.png  OK")
