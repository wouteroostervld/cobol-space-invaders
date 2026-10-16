#!/usr/bin/env python3
"""Record a scripted game of ./invaders and render it for the README.

A bot plays the real binary on a pty.  Every frame the game writes is
a full redraw of the 80x24 screen, so the output is split into frames,
replayed into a cell grid, drawn with Pillow (block and box characters
are drawn natively so rows join up) and encoded with ffmpeg.

    python3 tools/record.py            # docs/title.png, gameplay.mp4/.gif
"""
import fcntl, os, pty, re, select, struct, subprocess, sys, tempfile
import termios, time
from PIL import Image, ImageDraw, ImageFont

ROWS, COLS = 24, 80
CW, CH, PAD = 12, 24, 14          # cell size and margin in pixels
FPS = 25
MAX_SECONDS = 70
FONT = "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf"
BG = (10, 10, 20)
OUT = "docs"


# ---------------------------------------------------------------- terminal
class Screen:
    """Just enough of a terminal for the game's escape sequences."""
    SEQ = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")

    def __init__(self):
        self.cells = [[(" ", 231)] * COLS for _ in range(ROWS)]
        self.row = self.col = 0
        self.color = 231

    def feed(self, text):
        pos = 0
        for m in self.SEQ.finditer(text):
            self.put(text[pos:m.start()])
            pos = m.end()
            args, cmd = m.group(1), m.group(2)
            if cmd == "H":
                r, _, c = args.partition(";")
                self.row, self.col = int(r or 1) - 1, int(c or 1) - 1
            elif cmd == "m":
                p = args.split(";")
                self.color = int(p[2]) if p[:2] == ["38", "5"] else 231
            elif cmd == "J":
                self.cells = [[(" ", 231)] * COLS for _ in range(ROWS)]
        self.put(text[pos:])

    def put(self, s):
        for ch in s:
            if 0 <= self.row < ROWS and 0 <= self.col < COLS:
                self.cells[self.row][self.col] = (ch, self.color)
            self.col += 1

    def snapshot(self):
        return [row[:] for row in self.cells]


# ---------------------------------------------------------------- bot
def text_of(cells, r):
    return "".join(c for c, _ in cells[r])


def decide(cells):
    """Return the keys to press for one frame."""
    if "PRESS SPACE TO GO ON" in text_of(cells, 14):
        return b""
    ship = text_of(cells, 20)               # row 21 on screen
    if "▲" not in ship:
        return b""
    me = ship.index("▲")
    keys = b""
    # dodge: a bomb close above the ship in its column
    for r in range(14, 20):
        line = text_of(cells, r)
        for c in range(max(0, me - 2), min(COLS, me + 3)):
            if line[c] in "╱╲":
                return b"d" if c <= me and me < COLS - 4 else b"a"
    # target: the invader centre ('█' between sprite parts) nearest to us
    targets = []
    for r in range(3, 16):
        line = text_of(cells, r)
        for c in range(1, COLS - 1):
            if line[c] == "█" and line[c - 1] in "▞▚▜▟▛▙▄▀" \
                    and line[c + 1] in "▞▚▜▟▛▙▄▀":
                targets.append((r, c))
    if not targets:
        return b" "
    low = max(r for r, _ in targets)
    cols = [c for r, c in targets if r == low]
    t = min(cols, key=lambda c: abs(c - me))
    if t < me:
        keys += b"a"
    elif t > me:
        keys += b"d"
    if abs(t - me) <= 2 and "┃" not in "".join(text_of(cells, r)
                                               for r in range(2, 20)):
        keys += b" "
    return keys


def play(binary):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(TERM="xterm-256color", LANG="en_US.UTF-8",
                          PATH="/nonexistent")   # no audio player: silent
        os.execv(binary, [binary])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    screen, frames, buf = Screen(), [], b""
    t0, started, title_frames = time.time(), False, 0
    over_at = None
    while time.time() - t0 < MAX_SECONDS:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
        # a full frame always starts by homing the cursor
        parts = buf.split(b"\x1b[01;1H")
        buf = b"\x1b[01;1H" + parts[-1]
        for part in parts[:-1]:
            if not part:
                continue
            screen.feed("\x1b[01;1H" + part.decode("utf-8", "replace"))
            frames.append((time.time() - t0, screen.snapshot()))
            cells = frames[-1][1]
            if not started:
                title_frames += 1
                if title_frames > 60:        # ~2.5 s of title screen
                    os.write(fd, b" ")
                    started = True
            else:
                keys = decide(cells)
                if keys:
                    os.write(fd, keys)
                if "G A M E   O V E R" in "".join(text_of(cells, r)
                                                  for r in range(24)):
                    over_at = over_at or time.time()
        if over_at and time.time() - over_at > 3:
            break
    try:
        os.write(fd, b"q")
        time.sleep(0.2)
        os.write(fd, b"q")
        os.close(fd)
    except OSError:
        pass
    os.waitpid(pid, 0)
    return frames


# ---------------------------------------------------------------- drawing
font = ImageFont.truetype(FONT, 20)
BLOCKS = {  # quadrant glyphs: (upper-left, upper-right, lower-left, lower-right)
    "▘": "1000", "▝": "0100", "▖": "0010", "▗": "0001", "▚": "1001",
    "▞": "0110", "▛": "1110", "▜": "1101", "▙": "1011", "▟": "0111",
}


def xterm(n):
    if n < 16:
        base = [(0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
                (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
                (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
                (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
        return base[n]
    if n >= 232:
        v = 8 + (n - 232) * 10
        return (v, v, v)
    n -= 16
    lv = [0, 95, 135, 175, 215, 255]
    return (lv[n // 36], lv[n // 6 % 6], lv[n % 6])


def mix(c, a):
    return tuple(int(BG[i] + (c[i] - BG[i]) * a) for i in range(3))


def draw_cell(d, x, y, ch, rgb):
    cx, cy = x + CW // 2, y + CH // 2
    if ch == "█":
        d.rectangle([x, y, x + CW - 1, y + CH - 1], fill=rgb)
    elif ch == "▀":
        d.rectangle([x, y, x + CW - 1, y + CH // 2 - 1], fill=rgb)
    elif ch == "▄":
        d.rectangle([x, y + CH // 2, x + CW - 1, y + CH - 1], fill=rgb)
    elif ch in "░▒▓":
        a = {"░": .25, "▒": .5, "▓": .75}[ch]
        d.rectangle([x, y, x + CW - 1, y + CH - 1], fill=mix(rgb, a))
    elif ch in BLOCKS:
        for i, on in enumerate(BLOCKS[ch]):
            if on == "1":
                x0 = x + (i % 2) * CW // 2
                y0 = y + (i // 2) * CH // 2
                d.rectangle([x0, y0, x0 + CW // 2 - 1, y0 + CH // 2 - 1],
                            fill=rgb)
    elif ch in "═║╔╗╚╝":
        o = 2
        up, down = ch in "║╚╝", ch in "║╔╗"
        left, right = ch in "═╗╝", ch in "═╔╚"
        if ch == "═":
            d.rectangle([x, cy - o - 1, x + CW - 1, cy - o], fill=rgb)
            d.rectangle([x, cy + o - 1, x + CW - 1, cy + o], fill=rgb)
        elif ch == "║":
            d.rectangle([cx - o - 1, y, cx - o, y + CH - 1], fill=rgb)
            d.rectangle([cx + o - 1, y, cx + o, y + CH - 1], fill=rgb)
        else:
            sx = -1 if left else 1       # direction of the horizontal arm
            sy = -1 if up else 1         # direction of the vertical arm
            ex = x if left else x + CW - 1
            ey = y if up else y + CH - 1
            # outer and inner horizontal / vertical strokes
            for hy, vx in ((cy - sy * o, cx - sx * o),
                           (cy + sy * o, cx + sx * o)):
                x_lo, x_hi = sorted([vx, ex])
                d.rectangle([x_lo, hy - 1, x_hi, hy], fill=rgb)
                y_lo, y_hi = sorted([hy, ey])
                d.rectangle([vx - 1, y_lo, vx, y_hi], fill=rgb)
    elif ch in "╱╲":
        pts = [(x + 1, y + CH - 1), (x + CW - 1, y + 1)] if ch == "╱" \
            else [(x + 1, y + 1), (x + CW - 1, y + CH - 1)]
        d.line(pts, fill=rgb, width=2)
    elif ch == "┃":
        d.rectangle([cx - 1, y, cx, y + CH - 1], fill=rgb)
    elif ch == "│":
        d.rectangle([cx - 1, y, cx - 1, y + CH - 1], fill=rgb)
    elif ch == "╵":
        d.rectangle([cx - 1, y, cx - 1, cy], fill=rgb)
    elif ch == "─":
        d.rectangle([x, cy, x + CW - 1, cy], fill=rgb)
    elif ch == "┼":
        d.rectangle([cx - 1, y, cx - 1, y + CH - 1], fill=rgb)
        d.rectangle([x, cy, x + CW - 1, cy], fill=rgb)
    elif ch != " ":
        d.text((cx, cy), ch, font=font, fill=rgb, anchor="mm")


def render(cells):
    img = Image.new("RGB", (COLS * CW + 2 * PAD, ROWS * CH + 2 * PAD), BG)
    d = ImageDraw.Draw(img)
    for r in range(ROWS):
        for c in range(COLS):
            ch, n = cells[r][c]
            if ch != " ":
                draw_cell(d, PAD + c * CW, PAD + r * CH, ch, xterm(n))
    return img


# ---------------------------------------------------------------- output
def main():
    binary = os.path.abspath("invaders")
    if not os.path.exists(binary):
        sys.exit("build the game first: make")
    os.makedirs(OUT, exist_ok=True)
    frames = play(binary)
    if len(frames) < 100:
        sys.exit("recording failed: only %d frames" % len(frames))
    print("recorded %d frames, %.1f s" % (len(frames), frames[-1][0]))

    # title screenshot: a frame with the prompt showing
    for t, cells in frames[10:]:
        if "PRESS SPACE TO PLAY" in text_of(cells, 21):
            render(cells).save(os.path.join(OUT, "title.png"))
            break

    # resample to a constant frame rate
    total = int(frames[-1][0] * FPS)
    tmp = tempfile.mkdtemp()
    cache, k = {}, 0
    for n in range(total):
        while k + 1 < len(frames) and frames[k + 1][0] <= n / FPS:
            k += 1
        if k not in cache:
            cache[k] = os.path.join(tmp, "f%05d.png" % k)
            render(frames[k][1]).save(cache[k])
        os.link(cache[k], os.path.join(tmp, "o%05d.png" % n))
    mp4 = os.path.join(OUT, "gameplay.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate",
                    str(FPS), "-i", os.path.join(tmp, "o%05d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20",
                    mp4], check=True)
    gif = os.path.join(OUT, "gameplay.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf",
                    "fps=15,scale=720:-1:flags=lanczos,split[a][b];"
                    "[a]palettegen=max_colors=64[p];[b][p]paletteuse",
                    gif], check=True)
    print("wrote", mp4, gif)


if __name__ == "__main__":
    main()
