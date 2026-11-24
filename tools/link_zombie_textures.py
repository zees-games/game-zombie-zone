#!/usr/bin/env python3
"""Names each zombie body's texture inside its GLB, so a tool that reads only the GLB sees them.

    python3 tools/link_zombie_textures.py [--check]

The bodies are drawn with the view's palette shader and the atlas/albedo/normal PNGs it samples
(`ZzZombieView.ATLAS_OF`, `NORMALS`), so the GLBs were exported with no image at all: Nightly's Asset
Manager read them as untextured (NO_TEXTURES). This adds each body's images as relative URIs
(`atlas_basic.png`, `city_albedo_0.png`, `city_normal.png`) and points the material's base colour (and
normal) at them. The PNGs stay the one copy, nothing is embedded, so the pack does not grow; the Asset
Manager's viewer embeds them when it makes its copy. Idempotent. Run it after `build_zombie_models.py`
or any other export of these files. The mutant (vertex colours baked) and the oil monster (flat
colour by design) have no texture to name.
"""
import json, struct, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
DIR = os.path.join(HERE, "..", "assets", "zombies")

# body glb -> (albedo, normal or None); the same table as ZzZombieViewBase.ATLAS_OF and NORMALS.
BODIES = {
	"basic": ("atlas_basic.png", None), "chubby": ("atlas_heavy.png", None), "arm": ("atlas_heavy.png", None),
	"matt": ("atlas_people.png", None), "lis": ("atlas_people.png", None), "sam": ("atlas_people.png", None),
	"shaun": ("atlas_people.png", None), "worker": ("atlas_worker.png", None),
	"city": ("city_albedo_0.png", "city_normal.png"), "gent": ("gent_albedo.png", "gent_normal.png"),
	"cop": ("cop_albedo.png", "cop_normal.png"), "punk": ("punk_albedo.png", "punk_normal.png"),
	"convict": ("convict_albedo.png", "convict_normal.png"), "hazmat": ("hazmat_albedo.png", "hazmat_normal.png"),
	"walker": ("walker_albedo.png", "walker_normal.png"),
}


def read(path):
	b = open(path, "rb").read()
	n = struct.unpack("<I", b[12:16])[0]
	js = json.loads(b[20:20 + n])
	rest = b[20 + n:]
	return js, rest


def write(path, js, rest):
	data = json.dumps(js, separators=(",", ":")).encode()
	data += b" " * ((4 - len(data) % 4) % 4)
	total = 12 + 8 + len(data) + len(rest)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, total))
		f.write(struct.pack("<II", len(data), 0x4E4F534A) + data + rest)


def link(js, albedo, normal):
	js["images"] = [{"uri": u, "name": os.path.splitext(u)[0], "mimeType": "image/png"} for u in (albedo, normal) if u]
	js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
	js["textures"] = [{"sampler": 0, "source": i} for i in range(len(js["images"]))]
	for m in js.get("materials", []):
		m.setdefault("pbrMetallicRoughness", {})["baseColorTexture"] = {"index": 0}
		if normal:
			m["normalTexture"] = {"index": 1}
	return js


def main():
	check = "--check" in sys.argv
	bad = 0
	for body, (albedo, normal) in BODIES.items():
		path = os.path.join(DIR, "zombie_%s.glb" % body)
		for u in (albedo, normal):
			if u and not os.path.exists(os.path.join(DIR, u)):
				print("missing image", u); bad += 1
		js, rest = read(path)
		want = link(json.loads(json.dumps(js)), albedo, normal)
		if want == js:
			continue
		if check:
			print("not linked:", path); bad += 1
		else:
			write(path, want, rest); print("linked", os.path.basename(path), albedo, normal or "")
	sys.exit(1 if bad else 0)


main()
