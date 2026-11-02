"""Reference (golden) model for the FPGA image-processing pipeline.

Each function mirrors one hardware module so the RTL testbenches can compare
their output pixel-by-pixel against a trusted software result. This proves
algorithm correctness with no hardware.
"""
import os
import numpy as np

VEC_DIR = os.path.join("sim", "vectors")


def rgb2gray(rgb):
    """RGB888 (H,W,3) uint8 -> Y8 (H,W) uint8.  Y = (77R + 150G + 29B) >> 8."""
    r = rgb[..., 0].astype(np.uint16)
    g = rgb[..., 1].astype(np.uint16)
    b = rgb[..., 2].astype(np.uint16)
    return ((77 * r + 150 * g + 29 * b) >> 8).astype(np.uint8)


def write_hex(path, values, width_bits):
    """Write ints one-per-line as hex ($readmemh format)."""
    digits = (width_bits + 3) // 4
    mask = (1 << width_bits) - 1
    with open(path, "w") as fh:
        for v in values:
            fh.write("%0*x\n" % (digits, int(v) & mask))


def gen_gray_vectors(n_rand=1015, seed=1):
    """8 corner cases + n_rand random RGB triples, with expected Y."""
    corners = np.array([
        [0, 0, 0], [255, 255, 255], [255, 0, 0], [0, 255, 0], [0, 0, 255],
        [255, 255, 0], [0, 255, 255], [255, 0, 255], [128, 128, 128],
    ], dtype=np.uint8)
    rng = np.random.default_rng(seed)
    rnd = rng.integers(0, 256, size=(n_rand, 3)).astype(np.uint8)
    rgb = np.vstack([corners, rnd])
    r = rgb[:, 0].astype(np.uint16)
    g = rgb[:, 1].astype(np.uint16)
    b = rgb[:, 2].astype(np.uint16)
    y = ((77 * r + 150 * g + 29 * b) >> 8).astype(np.uint8)
    return rgb, y


def gen_lb_image(w=16, h=8, seed=7):
    """Small random test image for the 3x3 line-buffer window module."""
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(h, w)).astype(np.uint8)


def sobel_mag(img, thresh):
    """3x3 Sobel. Returns (mag, edge) uint16/uint8; edges of the image are 0."""
    im = img.astype(np.int16)
    gx = np.zeros_like(im)
    gy = np.zeros_like(im)
    gx[1:-1, 1:-1] = ((im[:-2, 2:] + 2 * im[1:-1, 2:] + im[2:, 2:]) -
                      (im[:-2, :-2] + 2 * im[1:-1, :-2] + im[2:, :-2]))
    gy[1:-1, 1:-1] = ((im[2:, :-2] + 2 * im[2:, 1:-1] + im[2:, 2:]) -
                      (im[:-2, :-2] + 2 * im[:-2, 1:-1] + im[:-2, 2:]))
    mag = (np.abs(gx) + np.abs(gy)).astype(np.uint16)
    edge = (mag >= thresh).astype(np.uint8)
    return mag, edge


def sobel_interior_mag(img, thresh=128):
    """Magnitude of interior pixels in raster order (matches the RTL stream)."""
    mag, _ = sobel_mag(img, thresh)
    h, w = img.shape
    return np.array([int(mag[y, x])
                     for y in range(1, h - 1)
                     for x in range(1, w - 1)], dtype=np.uint16)


def _sort3(a, b, c):
    h1, l1 = (a, b) if a > b else (b, a)
    h2, m2 = (h1, c) if h1 > c else (c, h1)
    mid, lo = (l1, m2) if l1 > m2 else (m2, l1)
    return lo, mid, h2


def _median_net(w):
    """Same sorting network as rtl/video/median3x3.v (for cross-checking)."""
    r0 = _sort3(w[0], w[1], w[2])
    r1 = _sort3(w[3], w[4], w[5])
    r2 = _sort3(w[6], w[7], w[8])
    a = max(r0[0], r1[0], r2[0])
    b = _sort3(r0[1], r1[1], r2[1])[1]
    c = min(r0[2], r1[2], r2[2])
    return _sort3(a, b, c)[1]


def median3x3_interior(img):
    """3x3 median of interior pixels in raster order (true median via sort)."""
    h, w = img.shape
    return np.array([int(np.sort(img[y-1:y+2, x-1:x+2].reshape(-1))[4])
                     for y in range(1, h - 1)
                     for x in range(1, w - 1)], dtype=np.uint8)


def debayer_bggr_interior(raw):
    """Bilinear demosaic of a BGGR Bayer image.

    Returns (r, g, b) lists for interior pixels in raster order, matching the
    RTL stream (line_buffer_3x3 + debayer).
    """
    h, w = raw.shape
    rr, gg, bb = [], [], []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            p  = int(raw[y, x])
            up = int(raw[y-1, x]); dn = int(raw[y+1, x])
            lf = int(raw[y, x-1]); rt = int(raw[y, x+1])
            ul = int(raw[y-1, x-1]); ur = int(raw[y-1, x+1])
            dl = int(raw[y+1, x-1]); dr = int(raw[y+1, x+1])
            havg = (lf + rt) >> 1
            vavg = (up + dn) >> 1
            davg = (ul + ur + dl + dr) >> 2
            cavg = (lf + rt + up + dn) >> 2
            py, px = y & 1, x & 1
            if py == 0 and px == 0:        # B
                r, g, b = davg, cavg, p
            elif py == 1 and px == 1:      # R
                r, g, b = p, cavg, davg
            elif py == 0 and px == 1:      # G
                r, g, b = vavg, p, havg
            else:                          # G
                r, g, b = havg, p, vavg
            rr.append(r); gg.append(g); bb.append(b)
    return (np.array(rr, dtype=np.uint8),
            np.array(gg, dtype=np.uint8),
            np.array(bb, dtype=np.uint8))


def gen_bayer_image(w=32, h=16, seed=11):
    rng = np.random.default_rng(seed)
    return rng.integers(0, 256, size=(h, w)).astype(np.uint8)


def pipeline_ref_bggr(bayer, thresh=128):
    """Full-chain reference: debayer -> gray -> median -> sobel.

    Returns (mag, edge) full images. Each stage only fills its interior, so the
    end-to-end valid region is x in [3, w-4], y in [3, h-4].
    """
    h, w = bayer.shape
    rgb = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            p  = int(bayer[y, x])
            up = int(bayer[y-1, x]); dn = int(bayer[y+1, x])
            lf = int(bayer[y, x-1]); rt = int(bayer[y, x+1])
            ul = int(bayer[y-1, x-1]); ur = int(bayer[y-1, x+1])
            dl = int(bayer[y+1, x-1]); dr = int(bayer[y+1, x+1])
            havg = (lf + rt) >> 1
            vavg = (up + dn) >> 1
            davg = (ul + ur + dl + dr) >> 2
            cavg = (lf + rt + up + dn) >> 2
            py, px = y & 1, x & 1
            if py == 0 and px == 0:
                r, g, b = davg, cavg, p
            elif py == 1 and px == 1:
                r, g, b = p, cavg, davg
            elif py == 0 and px == 1:
                r, g, b = vavg, p, havg
            else:
                r, g, b = havg, p, vavg
            rgb[y, x] = (r, g, b)

    gray = np.zeros((h, w), dtype=np.uint8)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            gray[y, x] = rgb2gray(rgb[y, x].reshape(1, 1, 3))[0, 0]

    med = np.zeros((h, w), dtype=np.uint8)
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            med[y, x] = int(np.sort(gray[y-1:y+2, x-1:x+2].reshape(-1))[4])

    mag, edge = sobel_mag(med, thresh)
    return mag, edge


def main():
    os.makedirs(VEC_DIR, exist_ok=True)
    rgb, y = gen_gray_vectors()
    rgb24 = ((rgb[:, 0].astype(np.uint32) << 16) |
             (rgb[:, 1].astype(np.uint32) << 8) |
             rgb[:, 2].astype(np.uint32))
    write_hex(os.path.join(VEC_DIR, "gray_rgb.hex"), rgb24, 24)
    write_hex(os.path.join(VEC_DIR, "gray_exp.hex"), y, 8)
    print("wrote %d grayscale vectors to %s/" % (len(y), VEC_DIR))

    img = gen_lb_image()
    write_hex(os.path.join(VEC_DIR, "lb_img.hex"), img.reshape(-1), 8)
    print("wrote %dx%d line-buffer test image (%d pixels)" %
          (img.shape[1], img.shape[0], img.size))

    mag = sobel_interior_mag(img)
    write_hex(os.path.join(VEC_DIR, "sobel_exp.hex"), mag, 12)
    print("wrote %d sobel magnitudes (interior pixels)" % len(mag))

    # cross-check the RTL sorting network against the true median
    rng = np.random.default_rng(3)
    for _ in range(20000):
        w = rng.integers(0, 256, 9)
        assert _median_net(w) == int(np.sort(w)[4]), "median network mismatch"
    med = median3x3_interior(img)
    write_hex(os.path.join(VEC_DIR, "median_exp.hex"), med, 8)
    print("wrote %d median values (interior pixels)" % len(med))

    dr, dg, db = debayer_bggr_interior(img)
    write_hex(os.path.join(VEC_DIR, "debayer_exp_r.hex"), dr, 8)
    write_hex(os.path.join(VEC_DIR, "debayer_exp_g.hex"), dg, 8)
    write_hex(os.path.join(VEC_DIR, "debayer_exp_b.hex"), db, 8)
    print("wrote %d debayer RGB triples (interior pixels)" % len(dr))

    # ---- full-chain (end-to-end) vectors ----
    bayer = gen_bayer_image()
    write_hex(os.path.join(VEC_DIR, "pipeline_bayer.hex"), bayer.reshape(-1), 8)
    mag_full, _ = pipeline_ref_bggr(bayer)
    h, w = bayer.shape
    region = mag_full[3:h-3, 3:w-3].reshape(-1)
    write_hex(os.path.join(VEC_DIR, "pipeline_exp.hex"), region, 12)
    print("wrote %dx%d bayer image and %d end-to-end sobel magnitudes"
          % (w, h, len(region)))

    # full-image magnitude reference, indexed by (x, y) -- for tb_alg_top
    write_hex(os.path.join(VEC_DIR, "alg_exp.hex"), mag_full.reshape(-1), 12)
    print("wrote full-image magnitude reference for alg_top (%d pixels)"
          % mag_full.size)


if __name__ == "__main__":
    main()
