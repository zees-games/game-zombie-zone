"""Paints the city common's colour maps: assets/zombies/city_albedo_<n>.png, one per look.

    python3 art-src/zombie_city_paint.py <bake dir> <out dir>

`<bake dir>` is what `zombie_city.py` wrote: the raw bake of the CC0 mesh's own colour (`city_albedo.png`, a dim
red-brown with the wounds in it), the masks (`city_mask_a.png`: skin, height, scalp; `city_mask_b.png`: face,
extremities, arm-ness) The source colour is not used as colour: it only says where the wounds
and folds are. Skin, cloth, hair, veins, lividity, dirt and blood are painted here, so the one mesh gets several
people (skin tone, outfit, hair, how bloody) without a second draw call or a second mesh.
"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

bake, out = sys.argv[1:3]
os.makedirs(out, exist_ok=True)


def load(name):
	return np.asarray(Image.open(os.path.join(bake, name)).convert("RGB"), dtype=np.float32) / 255.0


raw = load("city_albedo.png")
ma, mb, mc = load("city_mask_a.png"), load("city_mask_b.png"), load("city_mask_c.png")
H, W = ma.shape[:2]
skin_m, height, scalp_m = ma[:, :, 0], ma[:, :, 1], ma[:, :, 2]
face_m, extr_m = mb[:, :, 0], mb[:, :, 1]
eyes_m, mouth_m, lat_m = mc[:, :, 0], mc[:, :, 1], mc[:, :, 2]
# Texels no face covers (the bake's margin fills them with the nearest island, which is fine).
covered = (ma[:, :, 1] > 0.0) | (ma[:, :, 0] > 0.0)


def fbm(seed, base, octaves=5, gain=0.55):
	rng = np.random.default_rng(seed)
	acc = np.zeros((H, W), np.float32)
	amp = 1.0
	total = 0.0
	for o in range(octaves):
		n = max(2, base * 2 ** o)
		g = rng.random((n, n)).astype(np.float32)
		g = ndi.zoom(g, (H / n, W / n), order=3, mode="grid-wrap")[:H, :W]
		acc += g * amp
		total += amp
		amp *= gain
	acc /= total
	return (acc - acc.min()) / (acc.max() - acc.min() + 1e-6)


def blur(a, s):
	return ndi.gaussian_filter(a, s)


# Wounds: where the source is red against its own brightness.
r, g, b = raw[:, :, 0], raw[:, :, 1], raw[:, :, 2]
redness = np.clip((r - 0.5 * (g + b)) / (r + 0.04), 0.0, 1.0)
wound = np.clip((redness - 0.6) / 0.15, 0.0, 1.0)
wound = blur(wound, 1.2)
wound_halo = np.clip(blur(wound, 7.0) * 2.2, 0.0, 1.0)
detail = blur(raw.mean(axis=2), 0.7)
detail = (detail - blur(detail, 14)) * 1.5

# Which cloth: the torso garment above the hips, trousers below.
top_m = (skin_m < 0.5) & (height > 0.55)
bottom_m = (skin_m < 0.5) & (height <= 0.55)

LOOKS = [
	# skin, shirt, trousers, hair (None: bald), wound strength, dirt
	dict(skin=(0.69, 0.68, 0.58), shirt=(0.62, 0.64, 0.66), trousers=(0.20, 0.27, 0.40), hair=(0.10, 0.08, 0.07), wounds=0.9, dirt=0.35),
	dict(skin=(0.74, 0.66, 0.50), shirt=(0.45, 0.20, 0.17), trousers=(0.30, 0.28, 0.22), hair=(0.38, 0.27, 0.16), wounds=0.7, dirt=0.45),
	dict(skin=(0.58, 0.62, 0.64), shirt=(0.19, 0.25, 0.33), trousers=(0.13, 0.13, 0.14), hair=(0.62, 0.60, 0.55), wounds=1.0, dirt=0.3),
	dict(skin=(0.45, 0.34, 0.26), shirt=(0.58, 0.55, 0.45), trousers=(0.17, 0.20, 0.17), hair=None, wounds=0.8, dirt=0.5),
	dict(skin=(0.78, 0.70, 0.62), shirt=(0.15, 0.17, 0.15), trousers=(0.24, 0.30, 0.42), hair=(0.55, 0.42, 0.22), wounds=0.6, dirt=0.4),
	dict(skin=(0.52, 0.55, 0.40), shirt=(0.40, 0.33, 0.22), trousers=(0.22, 0.20, 0.30), hair=(0.06, 0.05, 0.05), wounds=1.0, dirt=0.6),
]

lum = lambda c: c @ np.array([0.3, 0.55, 0.15], np.float32)


def paint(i, look):
	seed = 100 + i
	blotch = fbm(seed, 3, 5)
	fine = fbm(seed + 1, 64, 2, 0.6)
	weave = fbm(seed + 2, 256, 1)
	veins_n = fbm(seed + 3, 6, 4, 0.5)
	veins = np.clip(1.0 - np.abs(veins_n - 0.5) * 22.0, 0, 1) ** 2
	smear = fbm(seed + 4, 5, 5)
	stain = fbm(seed + 5, 4, 5, 0.6)

	skin = np.array(look["skin"], np.float32)
	img = np.zeros((H, W, 3), np.float32)
	img[:] = skin
	# Blotchy, uneven dead skin: lividity (purple-blue) in the low and distal parts, sallow (yellow-green) elsewhere.
	liv = np.clip(0.55 * extr_m + 0.5 * (1.0 - height) * 0.6 + (blotch - 0.5) * 0.9, 0, 1)[:, :, None]
	img = img * (0.82 + 0.34 * blotch[:, :, None])
	img = img * (1 - 0.35 * liv) + np.array([0.45, 0.40, 0.55], np.float32) * 0.35 * liv * lum(img)[:, :, None] * 1.6
	img *= (0.93 + 0.14 * fine)[:, :, None]
	# Veins on the limbs, dark blue-green.
	vein = veins * (0.35 + 0.65 * lat_m) * (0.4 + 0.6 * smear)
	img = img * (1 - 0.35 * vein[:, :, None]) + np.array([0.20, 0.28, 0.30], np.float32) * 0.35 * vein[:, :, None]

	# Hair on the scalp, with strand noise; a face gets sunken, shadowed eyes and a darker mouth zone.
	if look["hair"] is not None:
		hair = np.array(look["hair"], np.float32)
		strand = fbm(seed + 6, 300, 1)
		hc = hair * (0.65 + 0.7 * strand[:, :, None]) * (0.8 + 0.4 * fine[:, :, None])
		a = blur(scalp_m, 1.5)[:, :, None]
		img = img * (1 - a) + hc * a
	else:
		# Bald: a darker, scabbed crown instead.
		a = (blur(scalp_m, 2.0) * 0.35)[:, :, None]
		img = img * (1 - a) + np.array([0.35, 0.22, 0.2], np.float32) * a
	# Face: dark rings around the eyes and a bruised mouth, from the face mask's gradient (the source face is baked in).
	fm = blur(face_m, 2.0)
	img *= (1.0 - 0.12 * fm * (0.5 + 0.5 * smear))[:, :, None]
	# Sunken, bruised eye sockets with a dull, bloodshot eye in them; a dark open mouth.
	sock = np.clip(blur(eyes_m, 1.5) * 1.4, 0, 1)[:, :, None]
	img = img * (1 - 0.75 * sock) + np.array([0.16, 0.09, 0.11], np.float32) * 0.75 * sock
	ball = np.clip((blur(eyes_m, 1.0) - 0.78) * 6.0, 0, 1)[:, :, None]
	img = img * (1 - ball) + np.array([0.72, 0.66, 0.46], np.float32) * (0.8 + 0.4 * fine[:, :, None]) * ball
	pupil = np.clip((blur(eyes_m, 1.0) - 0.93) * 14.0, 0, 1)[:, :, None]
	img = img * (1 - pupil) + np.array([0.05, 0.03, 0.02], np.float32) * pupil
	mth = np.clip(blur(mouth_m, 1.5) * 1.3, 0, 1)[:, :, None]
	img = img * (1 - 0.8 * mth) + np.array([0.14, 0.04, 0.05], np.float32) * 0.8 * mth

	# Cloth over the skin where the mesh is cloth.
	cl = np.zeros((H, W, 3), np.float32)
	cl[:] = np.array(look["shirt"], np.float32)
	tr = np.zeros((H, W, 3), np.float32)
	tr[:] = np.array(look["trousers"], np.float32)
	cloth = np.where(top_m[:, :, None], cl, tr)
	cloth = cloth * (0.78 + 0.5 * detail[:, :, None] * 0 + 0.32 * stain[:, :, None]) * (0.88 + 0.24 * weave[:, :, None])
	cloth = cloth * (1.0 + np.clip(detail, -0.5, 0.5)[:, :, None] * 0.6)
	# Dirt grows toward the ground and on the lower sleeves.
	dirt_amt = np.clip((1.0 - height) * 1.2 + (smear - 0.5) * 1.6, 0, 1) * look["dirt"]
	cloth = cloth * (1 - 0.55 * dirt_amt[:, :, None]) + np.array([0.22, 0.17, 0.12], np.float32) * 0.55 * dirt_amt[:, :, None]
	m = (skin_m < 0.5)[:, :, None]
	img = np.where(m, cloth, img)
	skin_dirt = np.clip((smear - 0.55) * 3.0, 0, 1) * look["dirt"] * (skin_m)
	img = img * (1 - 0.45 * skin_dirt[:, :, None]) + np.array([0.25, 0.20, 0.15], np.float32) * 0.45 * skin_dirt[:, :, None]

	# Blood: dried splashes where two noises agree, a stain halo round every wound, then the wound itself.
	splash = np.clip((blotch * 0.5 + stain * 0.5 - (0.78 - 0.08 * look["wounds"])) * 9.0, 0, 1) * np.clip(fine * 1.8, 0, 1)
	dried = np.array([0.24, 0.045, 0.04], np.float32) * (0.75 + 0.5 * fine[:, :, None])
	fresh = np.array([0.36, 0.04, 0.04], np.float32)
	deep = np.array([0.12, 0.015, 0.02], np.float32)
	clear = (1.0 - 0.9 * blur(np.maximum(face_m, scalp_m), 3.0))
	splash = splash * clear * 0.6
	img = img * (1 - 0.8 * splash[:, :, None]) + dried * 0.8 * splash[:, :, None]
	halo = (wound_halo * look["wounds"] * (0.25 + 0.4 * stain) * clear)[:, :, None]
	img = img * (1 - 0.6 * halo) + dried * 0.6 * halo
	w = (wound * look["wounds"] * 0.8 * clear)[:, :, None]
	wc = deep * (0.8 + 0.4 * fine[:, :, None])
	wc = wc + (fresh - wc) * np.clip(blur(wound, 2.0) - 0.4, 0, 1)[:, :, None] * 1.5
	# Flesh showing at the rim of a wound on skin.
	rim = np.clip(blur(wound, 2.0) - wound, 0, 1)[:, :, None]
	img = img * (1 - w) + wc * w
	img = img * (1 - 0.5 * rim) + np.array([0.55, 0.22, 0.2], np.float32) * 0.5 * rim * (skin_m[:, :, None])

	img = np.clip(img * 1.05, 0, 1)
	return img


for i, look in enumerate(LOOKS):
	im = paint(i, look)
	Image.fromarray((np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "city_albedo_%d.png" % i), optimize=True)
	print("painted", i)
