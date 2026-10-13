"""Generates the surface maps for the worlds seen from orbit (assets/planets/*.jpg).

Equirectangular, longitude -180..180 left to right, latitude 90..-90 top to bottom: 2048 x 1024 for
Sol's worlds, 1024 x 512 for the rest. Each lived-on world also gets a `<id>_mask.jpg` at half size:
red is water (it shines), green is city lights (they glow on the night side), blue is lava (it glows
everywhere, dimly by day).

Sol's worlds are the real ones:
- earth.jpg: real coastlines from the `global-land-mask` package (NOAA GLOBE data, public domain;
  the package is MIT), coloured by a rough climate: ice caps, tundra, forest, grassland, the big
  deserts, and shallow water along the coasts.
- mars.jpg: rust plains, darker albedo markings where the real ones are (roughly), and polar caps.
- luna.jpg: grey highlands with the near-side maria placed where they are, so the face is the face.
- venus, jupiter, saturn, europa, titan: cloud tops and ice, from the real look of each.

The other systems' worlds are invented from the canon in data/world/worlds.json (each function says
which line of the canon it draws on). They are meant to look lived-on without looking like Earth.

Needs numpy, Pillow and global-land-mask:
    pip install numpy pillow global-land-mask
    python3 tools/make_planet_maps.py
"""
import os

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "planets")
W = H = 0
LON = LAT = None


def grid(w, h):
    """Set the map size every helper below works at."""
    global W, H, LON, LAT
    W, H = w, h
    lon = np.linspace(-180, 180, W, endpoint=False) + 180.0 / W
    lat = np.linspace(90, -90, H, endpoint=False) - 90.0 / H
    LON, LAT = np.meshgrid(lon, lat)


grid(2048, 1024)


def noise(seed, scale, octaves=5):
    """Fractal noise in the map: blurred random fields at several sizes, wrapping east-west.
    `scale` is roughly how many blobs fit round the equator at the coarsest size. Returns about -0.5..0.5."""
    from scipy.ndimage import gaussian_filter
    rng = np.random.default_rng(seed)
    total = np.zeros((H, W))
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        sigma = W / (scale * (2 ** o)) / 2.5
        f = gaussian_filter(rng.normal(size=(H, W)), sigma=(sigma, sigma), mode=("nearest", "wrap"))
        total += amp * f / (f.std() + 1e-9)
        norm += amp
        amp *= 0.55
    total /= norm
    total *= 0.4 + 0.6 * np.cos(np.radians(LAT))   # the map stretches toward the poles: calm it there
    return np.clip(total * 0.25, -0.5, 0.5)


def craters(seed, count, rmin, rmax):
    """A crater field: darker floors and soft bright rims, sizes in degrees. Returns (darken, brighten)."""
    rng = np.random.default_rng(seed)
    dark = np.zeros((H, W))
    bright = np.zeros((H, W))
    for _ in range(count):
        r = rmin * (rmax / rmin) ** rng.random() ** 2.5
        la = float(np.degrees(np.arcsin(rng.uniform(-0.95, 0.95))))
        lo = rng.uniform(-180, 180)
        # Only the patch round the crater, wrapping east-west.
        rows = slice(max(0, int((90 - la - r * 1.6) / 180 * H)), min(H, int((90 - la + r * 1.6) / 180 * H) + 1))
        span = r * 1.6 / max(np.cos(np.radians(la)), 0.15)
        cols = np.arange(int((lo - span + 180) / 360 * W), int((lo + span + 180) / 360 * W) + 1) % W
        sub_lat = LAT[rows][:, cols]
        sub_lon = LON[rows][:, cols]
        dlon = (sub_lon - lo + 180) % 360 - 180
        d = np.sqrt(((sub_lat - la) / r) ** 2 + (dlon * np.cos(np.radians(sub_lat)) / r) ** 2)
        floor = np.clip(1 - d, 0, 1) ** 0.7 * 0.35
        rim = np.exp(-((d - 1.0) / 0.3) ** 2) * 0.22 * (d > 0.75)
        dark[rows, cols] = np.maximum(dark[rows, cols], floor)
        bright[rows, cols] = np.maximum(bright[rows, cols], rim)
    return dark, bright


def field(*blobs):
    """A smooth regional field from wide soft ellipses (lat, lon, lat radius, lon radius)."""
    total = np.zeros((H, W))
    for la, lo, rla, rlo in blobs:
        dlon = (LON - lo + 180) % 360 - 180
        total += np.exp(-(((LAT - la) / rla) ** 2 + (dlon / rlo) ** 2))
    return total


def edge(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def blob(lat0, lon0, rlat, rlon):
    """A soft ellipse, 1 inside fading to 0, wrapping in longitude."""
    dlon = (LON - lon0 + 180) % 360 - 180
    d = ((LAT - lat0) / rlat) ** 2 + (dlon / rlon) ** 2
    return np.clip(1.2 - d, 0, 1) ** 1.5


def save(name, rgb):
    os.makedirs(OUT, exist_ok=True)
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB")
    img.save(os.path.join(OUT, name), quality=88, optimize=True)
    print("wrote", name)


def save_mask(name, water, lights=None, lava=None):
    """The world's mask at half size: water (R), city lights (G), lava (B)."""
    z = np.zeros((H, W))
    rgb = np.stack([water, lights if lights is not None else z, lava if lava is not None else z], -1)
    img = Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8), "RGB").resize((W // 2, H // 2), Image.LANCZOS)
    img.save(os.path.join(OUT, name), quality=90, optimize=True)
    print("wrote", name)


def blurred(a, px):
    from scipy.ndimage import gaussian_filter
    return gaussian_filter(a.astype(np.float64), sigma=(px, px), mode=("nearest", "wrap"))


def ridges(seed, scale, octaves=4, sharp=10.0):
    """Ridged noise, 0..1: thin lines where the noise crosses zero (mountain belts, canyons), broken up
    so they read as chains rather than threads."""
    line = np.clip(1.0 - np.abs(noise(seed, scale, octaves)) * sharp, 0, 1) ** 3
    breaks = np.clip(noise(seed + 50, scale * 4, 3) * 4 + 0.6, 0, 1)
    return line * breaks


def chain_islands(seed, scale, amount):
    """Islands strung along arcs: the arcs from ridged noise, cut into separate islands by spotty noise."""
    arc = np.clip(1.0 - np.abs(noise(seed, scale, 4)) * 8.0, 0, 1)
    spots = noise(seed + 7, scale * 9, 3)
    return edge(arc * 0.7 + spots * 2.2, 1.0 - amount, 1.0 - amount + 0.08)


def land_at(field_, fraction):
    """Land where `field_` is in its top `fraction`: a soft 0..1 coastline."""
    t = np.quantile(field_, 1.0 - fraction)
    return edge(field_, t - 0.004, t + 0.004)


def lights_on(land, seed, density, coastal=0.6, scale=30.0):
    """City lights: fine specks on land, gathered into regions and along the coasts. `density` is how
    much of the land is in a lit region; inside one, only scattered specks are lit."""
    coast = np.clip(blurred(land, 3) * (1 - land) * 4 + land * (1 - blurred(land, 6)) * 3, 0, 1)
    region = noise(seed, scale, 3) + coast * coastal * 0.4
    t = np.quantile(region[land > 0.5], 1.0 - density) if (land > 0.5).any() else 1.0
    lit = np.clip((region - t) * 10.0, 0, 1) * land
    rng = np.random.default_rng(seed)
    specks = blurred((rng.random((H, W)) > 0.82).astype(float), 0.6) * 2.2
    return np.clip(lit * specks, 0, 1)


def earth():
    from global_land_mask import globe
    land = globe.is_land(LAT, LON).astype(np.float32)
    # Soften the edges a touch so the coast isn't a staircase from orbit.
    land_s = np.asarray(Image.fromarray((land * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    coast = np.asarray(Image.fromarray((land * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), np.float32) / 255.0
    n1 = noise(1, 3.0)
    n2 = noise(2, 9.0)
    alat = np.abs(LAT)

    deep = np.array([0.02, 0.07, 0.20])
    shallow = np.array([0.05, 0.22, 0.38])
    sea = deep + (shallow - deep) * np.clip(coast * 1.6, 0, 1)[..., None]

    forest = np.array([0.11, 0.22, 0.08])
    jungle = np.array([0.06, 0.17, 0.05])
    grass = np.array([0.33, 0.36, 0.17])
    desert = np.array([0.72, 0.58, 0.38])
    tundra = np.array([0.40, 0.37, 0.30])
    ice = np.array([0.92, 0.94, 0.97])

    n3 = noise(3, 14.0, 4)
    dry = field((23, 8, 9, 26), (21, 30, 8, 10), (24, 47, 8, 12), (-25, 128, 8, 16), (44, 103, 5, 16),
                (-23, 20, 5, 7), (33, -112, 5, 8), (-23, -69, 9, 3), (41, 62, 5, 14), (27, 70, 4, 5))
    dry = edge(dry + n3 * 2.6 + n1 * 0.8, 0.25, 0.95)
    wet = np.clip(1.0 - alat / 14.0 + n3 * 1.2, 0, 1)
    cold = np.clip((alat - 55) / 12.0 + n1 * 0.4, 0, 1)
    green = forest + (jungle - forest) * wet[..., None]
    green = green + (grass - green) * np.clip(0.5 + n2 * 1.2, 0, 1)[..., None] * 0.6
    ground = green + (desert - green) * dry[..., None]
    ground = ground + (tundra - ground) * cold[..., None]
    caps = np.clip((alat - 62) / 6.0, 0, 1) * (LAT < 0) + ((LAT > 59) & (LON > -74) & (LON < -10)) * 1.0
    caps = np.clip(caps + (alat > 78), 0, 1)
    ground = ground + (ice - ground) * caps[..., None]
    ground = ground * (0.92 + n2[..., None] * 0.5)
    rgb = sea + (ground - sea) * land_s[..., None]
    seaice = np.clip((alat - 72) / 6.0 + n2 * 0.6, 0, 1) * (1 - land_s)
    rgb = rgb + (ice * 0.9 - rgb) * seaice[..., None]
    save("earth.jpg", rgb)
    habitable = land_s * (1 - caps) * (1 - dry * 0.7) * (1 - cold * 0.8)
    save_mask("earth_mask.jpg", (1 - land_s) * (1 - seaice), lights_on(habitable, 4, 0.22, 0.9))


def mars():
    n1 = noise(7, 2.5)
    n2 = noise(8, 10.0, 4)
    base = np.array([0.62, 0.33, 0.19])
    light = np.array([0.76, 0.48, 0.30])
    dark = np.array([0.33, 0.20, 0.14])
    rgb = base + (light - base) * np.clip(0.5 + n1 * 1.5, 0, 1)[..., None]
    n3 = noise(9, 12.0, 4)
    marks = field((8, 70, 9, 10), (-22, 20, 9, 55), (-38, -60, 7, 45), (15, -10, 6, 20), (-12, 125, 10, 28))
    marks = edge(marks + n3 * 2.6 + n1 * 0.6, 0.2, 0.85)
    rgb = rgb + (dark - rgb) * marks[..., None]
    cd, cb = craters(10, 220, 0.5, 5.0)
    rgb = rgb * (1 - cd[..., None] * 0.35) + cb[..., None] * 0.12
    rgb = rgb * (0.9 + n2[..., None] * 0.4)
    caps = np.clip((LAT - 80) / 4.0 + n2 * 0.5, 0, 1) + np.clip((-LAT - 83) / 3.0 + n2 * 0.5, 0, 1)
    rgb = rgb + (np.array([0.93, 0.90, 0.86]) - rgb) * np.clip(caps, 0, 1)[..., None]
    save("mars.jpg", rgb)


def luna():
    n1 = noise(11, 4.0)
    n2 = noise(12, 22.0, 4)
    high = np.array([0.66, 0.65, 0.63])
    mare = np.array([0.30, 0.30, 0.31])
    # The near side faces longitude 0: Imbrium, Serenitatis, Tranquillitatis, Crisium, Fecunditatis,
    # Nectaris, Nubium, Humorum and the sprawl of Procellarum.
    n3 = noise(13, 16.0, 4)
    maria = field((33, -16, 14, 19), (28, 17, 9, 10), (8, 30, 10, 13), (17, 59, 5, 6), (-6, 50, 10, 8),
                  (-15, 35, 5, 5), (-20, -16, 9, 11), (-24, -39, 5, 6), (12, -52, 24, 15), (57, 0, 5, 30),
                  (-20, 160, 5, 6), (0, -15, 8, 8))
    maria = edge(maria + n3 * 2.4 + n1 * 0.4, 0.2, 0.75)
    rgb = high + (mare - high) * maria[..., None]
    cd, cb = craters(14, 700, 0.3, 6.0)
    rgb = rgb * (1 - cd[..., None] * 0.3 * (1 - maria[..., None] * 0.6)) + cb[..., None] * 0.18
    rgb = rgb * (0.92 + n2[..., None] * 0.4)
    # A few bright rayed craters: Tycho, Copernicus, Kepler.
    for la, lo, r in [(-43, -11, 2.2), (10, -20, 1.6), (8, -38, 1.0)]:
        rgb = rgb + (np.array([0.92, 0.92, 0.9]) - rgb) * blob(la, lo, r, r)[..., None]
    save("luna.jpg", rgb)



# ---- More of Sol ------------------------------------------------------------------------------

def bands(seed, colours, turbulence, count, storms=()):
    """A gas giant's cloud bands: `colours` alternate down the latitudes, stirred by `turbulence`."""
    n1 = noise(seed, 6.0, 5)
    n2 = noise(seed + 1, 18.0, 4)
    warp = LAT + n1 * turbulence * 40 + n2 * turbulence * 12
    t = (np.sin(np.radians(warp) * count) + 1) * 0.5
    t2 = (np.sin(np.radians(warp) * count * 2.3 + 1.0) + 1) * 0.5
    c = np.array(colours, dtype=float)
    rgb = c[0] + (c[1] - c[0]) * t[..., None]
    rgb = rgb + (c[2] - rgb) * (t2 ** 3)[..., None] * 0.5
    for la, lo, rla, rlo, col in storms:
        rgb = rgb + (np.array(col) - rgb) * blob(la, lo, rla, rlo)[..., None]
    return rgb * (0.95 + n2[..., None] * 0.2)


def venus():
    """Venus: nothing but cloud, yellow-white with faint dark chevrons."""
    n = noise(21, 3.0, 5)
    chev = np.sin(np.radians(LON * 2 + np.abs(LAT) * 3) + n * 4) * 0.5 + 0.5
    rgb = np.array([0.90, 0.84, 0.66]) + (np.array([0.76, 0.66, 0.46]) - np.array([0.90, 0.84, 0.66])) * (chev * 0.6)[..., None]
    save("venus.jpg", rgb * (0.95 + noise(22, 12, 3)[..., None] * 0.2))


def jupiter():
    rgb = bands(31, [[0.86, 0.80, 0.70], [0.66, 0.50, 0.38], [0.92, 0.90, 0.84]], 0.25, 9,
                storms=[(-22, 40, 6, 11, [0.72, 0.36, 0.24]), (-33, -80, 2.5, 4, [0.95, 0.93, 0.9])])
    save("jupiter.jpg", rgb)


def saturn():
    rgb = bands(41, [[0.88, 0.80, 0.62], [0.78, 0.68, 0.50], [0.93, 0.88, 0.74]], 0.12, 7)
    save("saturn.jpg", rgb)


def europa():
    n = noise(51, 8.0, 4)
    rgb = np.array([0.88, 0.85, 0.80]) * (0.95 + n[..., None] * 0.2)
    lines = np.clip(ridges(52, 4.0, 4) + ridges(53, 7.0, 3) * 0.7, 0, 1)
    rgb = rgb + (np.array([0.55, 0.38, 0.26]) - rgb) * (lines * 0.7)[..., None]
    save("europa.jpg", rgb)


def titan():
    n = noise(61, 3.0, 4)
    rgb = np.array([0.80, 0.56, 0.25]) * (0.92 + n[..., None] * 0.25)
    save("titan.jpg", rgb)


# ---- The other systems -----------------------------------------------------------------------
# Each lived-on world is built the same way: a continent field cut at the canon's land fraction,
# seas from deep to shallow over the shelves, ground coloured by height, wetness and cold, ice caps,
# and city lights where the canon puts people. The colours and the oddities come from worlds.json.

def terrestrial(name, seed, land_frac, deep, shallow, shelf, low, high, dry, cold, caps_lat,
                cont_scale=3.0, wet_bias=0.0, cities=0.1, coastal=0.6, extra=None):
    n_c = noise(seed, cont_scale, 6)
    n_h = noise(seed + 1, 10.0, 5)
    n_w = noise(seed + 2, 6.0, 4)
    land = land_at(n_c, land_frac)
    height = np.clip((n_c - np.quantile(n_c, 1 - land_frac)) * 5 + n_h * 1.5, 0, 1)
    near = np.clip(blurred(land, shelf), 0, 1)
    sea = np.array(deep) + (np.array(shallow) - np.array(deep)) * np.clip(near * 1.8 + n_h * 0.4, 0, 1)[..., None]
    alat = np.abs(LAT)
    wet = np.clip(0.5 + n_w * 2.0 + wet_bias, 0, 1)
    ground = np.array(low) + (np.array(high) - np.array(low)) * height[..., None]
    ground = ground + (np.array(dry) - ground) * (1 - wet)[..., None] * 0.8
    coldness = np.clip((alat - caps_lat + 25) / 25.0 + n_h, 0, 1)
    ground = ground + (np.array(cold) - ground) * coldness[..., None]
    ground = ground * (0.9 + n_h[..., None] * 0.4)
    ice = np.clip((alat - caps_lat - 6 * (1 - land)) / 4.0 + n_w * 1.0, 0, 1)
    rgb = sea + (ground - sea) * land[..., None]
    rgb = rgb + (np.array([0.92, 0.93, 0.95]) - rgb) * ice[..., None]
    ctx = {"land": land, "height": height, "wet": wet, "ice": ice, "alat": alat, "lava": None}
    if extra is not None:
        rgb = extra(rgb, ctx)
    water = (1 - land) * (1 - ice)
    lights = lights_on(land * (1 - ice) * (1 - coldness * 0.7), seed + 9, cities, coastal) if cities > 0 else None
    save(name + ".jpg", rgb)
    save_mask(name + "_mask.jpg", water, lights, ctx["lava"])


def keshar():
    """'Shallow seas, broad continental shelves and rugged uplands'; dense air; a Kesh biosphere."""
    def uplands(rgb, c):
        r = ridges(105, 5.0) * c["land"]
        return rgb + (np.array([0.30, 0.20, 0.16]) - rgb) * (r * 0.6)[..., None]
    terrestrial("keshar_prime", 100, 0.42, [0.04, 0.16, 0.17], [0.16, 0.42, 0.38], 10,
                [0.32, 0.27, 0.14], [0.42, 0.24, 0.17], [0.55, 0.42, 0.28], [0.5, 0.45, 0.4], 72,
                cont_scale=2.5, cities=0.25, extra=uplands)


def ilos():
    """'Deep basins, immense escarpments and vertical geology'; a dense atmosphere, low gravity."""
    def scarps(rgb, c):
        r = ridges(115, 3.5, 5)
        rgb = rgb + (np.array([0.20, 0.17, 0.22]) - rgb) * (r * 0.75)[..., None]
        plateau = np.clip(c["height"] * 1.4 - 0.3, 0, 1) * c["land"]
        return rgb + (np.array([0.80, 0.74, 0.62]) - rgb) * (plateau * 0.6)[..., None]
    terrestrial("ilos_prime", 110, 0.62, [0.08, 0.10, 0.28], [0.22, 0.30, 0.55], 2,
                [0.16, 0.38, 0.34], [0.55, 0.52, 0.44], [0.62, 0.55, 0.42], [0.6, 0.6, 0.62], 76,
                cont_scale=4.0, cities=0.14, coastal=0.2, extra=scarps)


def veyara():
    """'Global ocean with island arcs and shallow continental seas'; humid, the Vey home."""
    def arcs(rgb, c):
        isl = chain_islands(125, 3.0, 0.06) * (1 - c["land"])
        shoal = np.clip(blurred(isl, 3) * 3, 0, 1) * (1 - isl)
        rgb = rgb + (np.array([0.12, 0.50, 0.46]) - rgb) * (shoal * 0.7)[..., None]
        rgb = rgb + (np.array([0.10, 0.30, 0.12]) - rgb) * isl[..., None]
        c["land"] = np.clip(c["land"] + isl, 0, 1)
        return rgb
    terrestrial("veyara_prime", 120, 0.10, [0.02, 0.12, 0.22], [0.10, 0.48, 0.48], 14,
                [0.10, 0.30, 0.13], [0.24, 0.36, 0.18], [0.40, 0.40, 0.25], [0.5, 0.55, 0.52], 80,
                cont_scale=5.0, wet_bias=0.4, cities=0.35, coastal=1.0, extra=arcs)


def orun():
    """'Rocky terrain with extreme diurnal temperature swings', dust loading; the Orun live underground."""
    def dust(rgb, c):
        d = noise(135, 4.0, 4)
        rgb = rgb + (np.array([0.70, 0.52, 0.30]) - rgb) * np.clip(0.4 + d * 1.5, 0, 0.7)[..., None]
        basalt = edge(noise(136, 6.0, 4), 0.05, 0.12) * c["land"]
        return rgb + (np.array([0.18, 0.15, 0.14]) - rgb) * (basalt * 0.8)[..., None]
    terrestrial("orun_prime", 130, 0.82, [0.05, 0.10, 0.14], [0.18, 0.26, 0.26], 2,
                [0.42, 0.30, 0.20], [0.24, 0.20, 0.18], [0.62, 0.46, 0.28], [0.55, 0.50, 0.46], 80,
                cont_scale=3.0, wet_bias=-0.4, cities=0.05, coastal=0.1, extra=dust)


def concord():
    """'Temperate continents and shallow inland seas'; layered trade cities. A greener, bluer Earth-cousin
    with one sprawling continent full of inland seas rather than oceans between continents."""
    def inland(rgb, c):
        lakes = land_at(noise(145, 9.0, 4), 0.14) * c["land"] * np.clip(c["height"] * -2 + 1.2, 0, 1)
        rgb = rgb + (np.array([0.10, 0.36, 0.40]) - rgb) * lakes[..., None]
        c["land"] = c["land"] * (1 - lakes)
        return rgb
    terrestrial("concord_prime", 140, 0.55, [0.03, 0.10, 0.25], [0.08, 0.30, 0.40], 5,
                [0.16, 0.30, 0.20], [0.36, 0.40, 0.30], [0.55, 0.50, 0.36], [0.45, 0.45, 0.42], 74,
                cont_scale=1.6, cities=0.45, coastal=0.8, extra=inland)


def roosevelt():
    """'Cold mineral-rich continents, mountain belts and inland seas'; snow, mines and orbital yards."""
    def snow(rgb, c):
        r = ridges(155, 4.0)
        rgb = rgb + (np.array([0.88, 0.90, 0.94]) - rgb) * (np.clip(r + c["height"] * 0.5, 0, 1) * c["land"] * 0.8)[..., None]
        return rgb
    terrestrial("roosevelt", 150, 0.45, [0.04, 0.09, 0.15], [0.18, 0.26, 0.32], 4,
                [0.20, 0.24, 0.22], [0.48, 0.48, 0.50], [0.45, 0.42, 0.38], [0.85, 0.87, 0.9], 55,
                cont_scale=2.8, cities=0.18, extra=snow)


def hesperus():
    """'Broad plains, shallow seas and long temperate growing belts'; huge fields."""
    def fields(rgb, c):
        belt = np.clip(1 - np.abs(c["alat"] - 35) / 18, 0, 1) * c["land"]
        patch = (noise(165, 45.0, 2) > 0).astype(float)
        patch = blurred(patch, 0.6)
        gold = np.array([0.70, 0.60, 0.30]) * patch[..., None] + np.array([0.36, 0.48, 0.18]) * (1 - patch[..., None])
        return rgb + (gold - rgb) * (belt * 0.75)[..., None]
    terrestrial("hesperus_prime", 160, 0.50, [0.04, 0.12, 0.24], [0.14, 0.36, 0.44], 8,
                [0.30, 0.40, 0.18], [0.46, 0.44, 0.30], [0.62, 0.55, 0.34], [0.5, 0.48, 0.44], 70,
                cont_scale=2.0, cities=0.08, coastal=0.4, extra=fields)


def iron_gate():
    """'Dry rocky continents with accessible mineral provinces'; casting works."""
    def ore(rgb, c):
        r = ridges(175, 6.0) * c["land"]
        streak = np.clip(noise(176, 12.0, 3) * 3, 0, 1) * c["land"]
        rgb = rgb + (np.array([0.55, 0.26, 0.16]) - rgb) * (streak * 0.45 + r * 0.3)[..., None]
        return rgb
    terrestrial("iron_gate_prime", 170, 0.68, [0.04, 0.10, 0.18], [0.20, 0.30, 0.34], 3,
                [0.62, 0.52, 0.42], [0.52, 0.46, 0.42], [0.74, 0.62, 0.48], [0.65, 0.62, 0.6], 78,
                cont_scale=3.0, wet_bias=-0.5, cities=0.2, coastal=0.3, extra=ore)


def bradbury():
    """'Cool plateaus, deep valleys and dry inland basins'; low pressure; campuses and observatories."""
    def basins(rgb, c):
        salt = land_at(noise(195, 7.0, 4), 0.12) * c["land"]
        rgb = rgb + (np.array([0.88, 0.86, 0.80]) - rgb) * (salt * 0.8)[..., None]
        valleys = ridges(196, 5.0) * c["land"]
        return rgb + (np.array([0.18, 0.34, 0.20]) - rgb) * (valleys * 0.7)[..., None]
    terrestrial("bradbury_prime", 190, 0.60, [0.05, 0.12, 0.24], [0.18, 0.32, 0.42], 3,
                [0.52, 0.42, 0.36], [0.62, 0.52, 0.46], [0.66, 0.56, 0.44], [0.62, 0.62, 0.64], 72,
                cont_scale=3.0, wet_bias=-0.3, cities=0.1, extra=basins)


def pelagos():
    """'Ocean with volcanic island chains'; warm and humid; joint Vey-human colony."""
    def chains(rgb, c):
        isl = chain_islands(205, 2.5, 0.05)
        reef = np.clip(blurred(isl, 2.5) * 3.5, 0, 1) * (1 - isl)
        rgb = rgb + (np.array([0.20, 0.62, 0.62]) - rgb) * (reef * 0.7)[..., None]
        rgb = rgb + (np.array([0.10, 0.18, 0.10]) - rgb) * isl[..., None]
        c["land"] = np.clip(c["land"] + isl, 0, 1)
        return rgb
    terrestrial("pelagos_prime", 200, 0.03, [0.01, 0.10, 0.30], [0.06, 0.36, 0.50], 4,
                [0.10, 0.20, 0.10], [0.16, 0.16, 0.14], [0.3, 0.3, 0.2], [0.5, 0.55, 0.5], 84,
                cont_scale=6.0, wet_bias=0.5, cities=0.3, coastal=1.0, extra=chains)


def tidemark():
    """'Almost continuous deep ocean', dense, wet and storm-prone; floating platforms."""
    terrestrial("tidemark_prime", 210, 0.02, [0.01, 0.05, 0.12], [0.04, 0.14, 0.22], 3,
                [0.18, 0.18, 0.16], [0.22, 0.22, 0.2], [0.3, 0.3, 0.26], [0.6, 0.62, 0.65], 74,
                cont_scale=7.0, cities=0.0)


def foundry():
    """'Hot volcanic uplands and tectonic basins', black rock and steam; factories underground."""
    def lava(rgb, c):
        cracks = ridges(225, 4.0, 5, sharp=28.0) * c["land"]
        c["lava"] = np.clip(cracks * 1.8 - 0.6, 0, 1)
        return rgb + (np.array([0.70, 0.22, 0.06]) - rgb) * (c["lava"] * 0.8)[..., None]
    terrestrial("foundry_prime", 220, 0.78, [0.06, 0.08, 0.10], [0.16, 0.18, 0.18], 2,
                [0.14, 0.13, 0.13], [0.26, 0.24, 0.22], [0.34, 0.28, 0.22], [0.45, 0.44, 0.42], 82,
                cont_scale=3.5, wet_bias=-0.6, cities=0.06, coastal=0.1, extra=lava)


def talos():
    """'Cold high desert, exposed mineral formations'; thin air; a mining boom."""
    def minerals(rgb, c):
        r = ridges(235, 5.0) * c["land"]
        rgb = rgb + (np.array([0.52, 0.30, 0.42]) - rgb) * (r * 0.5)[..., None]
        r2 = ridges(236, 9.0, 3) * c["land"]
        return rgb + (np.array([0.78, 0.66, 0.40]) - rgb) * (r2 * 0.4)[..., None]
    terrestrial("talos_prime", 230, 0.80, [0.06, 0.12, 0.18], [0.20, 0.28, 0.30], 2,
                [0.56, 0.44, 0.34], [0.66, 0.60, 0.54], [0.70, 0.56, 0.40], [0.8, 0.8, 0.82], 66,
                cont_scale=3.0, wet_bias=-0.7, cities=0.03, extra=minerals)


def lastlight():
    """'Rocky subpolar plains and low mountain chains'; cold, thin air; one lit settlement."""
    terrestrial("lastlight_settlement", 240, 0.58, [0.03, 0.07, 0.12], [0.12, 0.18, 0.24], 3,
                [0.30, 0.30, 0.26], [0.42, 0.40, 0.38], [0.40, 0.38, 0.32], [0.86, 0.88, 0.9], 48,
                cont_scale=3.0, cities=0.004)


# ---- Neighbours: the giants and moons named in data/world/system_bodies.json -------------------

GIANTS = {   # id: (seed, three band colours, turbulence, band count, canon line)
    "tor": (301, [[0.62, 0.42, 0.26], [0.44, 0.28, 0.18], [0.72, 0.56, 0.38]], 0.3, 8),          # Keshar's volatiles giant
    "elen": (302, [[0.82, 0.80, 0.90], [0.66, 0.62, 0.80], [0.90, 0.88, 0.95]], 0.15, 10),        # Ilos: research, fuel
    "oruvai": (303, [[0.42, 0.62, 0.56], [0.30, 0.48, 0.46], [0.60, 0.74, 0.66]], 0.2, 9),        # Veyara: chemical feedstocks
    "arbitrator": (304, [[0.84, 0.80, 0.70], [0.62, 0.68, 0.76], [0.90, 0.88, 0.80]], 0.18, 9),   # Concord: fuel
    "longhorn": (305, [[0.74, 0.54, 0.38], [0.58, 0.38, 0.26], [0.86, 0.72, 0.56]], 0.28, 8),     # New Houston: fuel, chemicals
    "rainmaker": (306, [[0.58, 0.64, 0.70], [0.44, 0.50, 0.58], [0.76, 0.80, 0.84]], 0.35, 7),    # Hesperus: gases, fertiliser
    "hammer": (307, [[0.46, 0.42, 0.40], [0.32, 0.30, 0.30], [0.60, 0.56, 0.52]], 0.22, 9),       # Iron Gate: fuel
    "breaker": (308, [[0.46, 0.66, 0.76], [0.32, 0.52, 0.66], [0.66, 0.80, 0.86]], 0.25, 9),      # Pelagos: fuel, research
    "stormhold": (309, [[0.26, 0.32, 0.48], [0.18, 0.22, 0.36], [0.44, 0.50, 0.64]], 0.45, 7),    # Tidemark: storms, science
    "prospector": (310, [[0.80, 0.72, 0.50], [0.64, 0.56, 0.38], [0.88, 0.82, 0.64]], 0.2, 8),    # Carver: fuel for the ore trade
    "meridian_host": (251, [[0.70, 0.74, 0.78], [0.52, 0.60, 0.66], [0.82, 0.84, 0.86]], 0.18, 8),  # Port Meridian's host giant
}


def giants():
    for gid, (seed, cols, turb, count) in GIANTS.items():
        storms = [(float(np.random.default_rng(seed).uniform(-40, 40)), float(np.random.default_rng(seed + 1).uniform(-180, 180)),
                   4, 7, [c * 0.9 for c in cols[1]])]
        save(gid + ".jpg", bands(seed, cols, turb, count, storms))


def rocks():
    """Airless neighbours: grey cratered rock, dark sun-baked rock, and dirty ice."""
    for name, seed, base, dark in [("rock_grey", 401, [0.52, 0.50, 0.48], [0.30, 0.29, 0.28]),
                                   ("rock_dark", 402, [0.34, 0.30, 0.28], [0.18, 0.16, 0.15]),
                                   ("ice_dirty", 403, [0.80, 0.82, 0.84], [0.52, 0.56, 0.60])]:
        n = noise(seed, 6.0, 5)
        rgb = np.array(base) + (np.array(dark) - np.array(base)) * edge(n, -0.05, 0.15)[..., None]
        cd, cb = craters(seed + 1, 260, 0.6, 7.0)
        rgb = rgb * (1 - cd[..., None] * 0.35) + cb[..., None] * 0.15
        save(name + ".jpg", rgb * (0.92 + noise(seed + 2, 20, 3)[..., None] * 0.3))


if __name__ == "__main__":
    import sys
    only = set(sys.argv[1:])
    grid(2048, 1024)
    for f in [earth, mars, luna, venus, jupiter, saturn]:
        if not only or f.__name__ in only:
            f()
    grid(1024, 512)
    for f in [europa, titan, keshar, ilos, veyara, orun, concord, roosevelt, hesperus, iron_gate,
              bradbury, pelagos, tidemark, foundry, talos, lastlight, giants, rocks]:
        if not only or f.__name__ in only:
            f()
