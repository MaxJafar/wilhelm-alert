#!/usr/bin/env python3
"""The scream overlay for Linux.

A borderless, always-on-top Tk window near the corner of the screen. Tkinter
is the only GUI toolkit reliably present across desktops without pulling in
a dependency, so it's what this uses.

    overlay-linux.py --image face.png [--mode turbo] [--seconds 2.4]
"""

import argparse
import math
import sys

try:
    import tkinter as tk
except ImportError:
    sys.stderr.write("wilhelm-overlay: python3 tkinter is not installed\n")
    sys.exit(1)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--image", required=True)
    parser.add_argument("--mode", default="middle")
    parser.add_argument("--seconds", type=float, default=2.4)
    args = parser.parse_args()

    side = 300 if args.mode == "turbo" else 240

    root = tk.Tk()
    root.overrideredirect(True)  # no titlebar or borders
    root.attributes("-topmost", True)

    # Tk only reads GIF/PGM/PPM natively; Pillow covers PNG and everything
    # else. Without it we bail rather than showing an empty window.
    photo = None
    try:
        from PIL import Image, ImageTk  # type: ignore

        image = Image.open(args.image)
        image.thumbnail((side, side))
        photo = ImageTk.PhotoImage(image)
    except ImportError:
        try:
            photo = tk.PhotoImage(file=args.image)
        except tk.TclError:
            sys.stderr.write(
                "wilhelm-overlay: cannot read this image format.\n"
                "  Install Pillow (pip install Pillow) or use a .gif face.\n"
            )
            return 1

    label = tk.Label(root, image=photo, borderwidth=0, highlightthickness=0)
    label.pack()

    root.update_idletasks()
    width = photo.width()
    height = photo.height()
    margin = 28
    base_x = root.winfo_screenwidth() - width - margin
    base_y = root.winfo_screenheight() - height - margin - 40  # clear most panels
    root.geometry(f"+{base_x}+{base_y}")

    root.bind("<Button-1>", lambda _event: root.destroy())

    if args.mode == "turbo":
        duration = 0.62
        step_ms = 16

        def shake(elapsed: float = 0.0) -> None:
            if elapsed >= duration:
                root.geometry(f"+{base_x}+{base_y}")
                return
            # Decaying sine rather than random offsets: random reads as a
            # glitch, this reads as something being physically rattled.
            decay = (1.0 - elapsed / duration) ** 1.7
            amplitude = 34.0 * decay
            offset_x = int(amplitude * math.sin(elapsed * 58.0))
            offset_y = int(amplitude * 0.55 * math.sin(elapsed * 79.0 + 1.1))
            root.geometry(f"+{base_x + offset_x}+{base_y + offset_y}")
            root.after(step_ms, lambda: shake(elapsed + step_ms / 1000.0))

        root.after(10, shake)

    root.after(int(args.seconds * 1000), root.destroy)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
