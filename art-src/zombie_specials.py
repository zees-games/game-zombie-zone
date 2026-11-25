"""Builds the six special zombies' bodies: assets/zombies/zombie_<kind>.glb plus <kind>_albedo.png and <kind>_normal.png.

    blender -b --factory-startup --python art-src/zombie_specials.py -- <kit dir> <out dir> <kind>[,<kind>...] [--bake-size=1024] [--sheet]

kinds: brute bloater strangler spitter sleeper screamer.

The skeleton, the skin weights and the clips are the Quaternius Zombie Apocalypse Kit's (CC0 1.0,
https://quaternius.com/packs/zombieapocalypsekit.html), through `tools/build_zombie_models.py`: the
brute, bloater and screamer start from zombie_chubby.glb, the strangler from zombie_basic.glb, the
spitter and sleeper from zombie_lis.glb. What is ours, as in `art-src/zombie_worker.py`: each kind's
silhouette modelled on top of that body (armour and spikes, boils and a swollen belly, a rope and a
hooded rag cloak, acid sacs, a hospital gown, a robe and a bone crest), each piece weighted whole to
one bone; the kit atlas recoloured to the kind's palette; and one baked 1024 albedo (colour, grime,
veins, blood, ambient occlusion) plus one tangent normal map on a fresh UV layout, so the body is one
mesh, one material, one draw call. Procedural throughout: no other artist's work is in these files.
"""
import bpy, bmesh, sys, os, math, random, mathutils
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
KIT, OUT, KINDS = args[0], args[1], args[2].split(",")
BAKE = 1024
SHEET = False
PARAMS = {}
for a in args[3:]:
	if a.startswith("--bake-size="):
		BAKE = int(a.split("=")[1])
	if a == "--sheet":
		SHEET = True
os.makedirs(OUT, exist_ok=True)

CLIPS = {"Crawl": "crawl", "Death": "death", "HitReact": "hit", "Idle": "idle", "Idle_Attack": "attack_idle",
	"Jump": "jump", "Jump_Idle": "jump_idle", "Jump_Land": "jump_land", "Punch": "attack", "Run": "run",
	"Run_Arms": "run_arms", "Run_Attack": "attack_run", "Walk": "walk"}

# kind -> kit body, its atlas, the swatches the kit paints (skin/top/bottom/belt/hair, ZzZombieViewBase.WEARS)
# and the colour each becomes, then the skin's vein colour/amount and the blood amount.
SPEC = {
	"brute": dict(body="chubby", atlas="atlas_heavy.png", swap={"5f6397": "86483a", "63503f": "2a2523"}, vein=((0.16, 0.03, 0.04, 1), 0.8, 7.0), blood=0.7, bump=0.7),
	"bloater": dict(body="chubby", atlas="atlas_heavy.png", swap={"5f6397": "bdb560", "63503f": "5a4a2c"}, vein=((0.34, 0.5, 0.1, 1), 0.85, 5.0), blood=0.45, bump=0.5),
	"screamer": dict(body="chubby", atlas="atlas_heavy.png", swap={"5f6397": "c3ccd8", "63503f": "571a2c"}, vein=((0.32, 0.38, 0.62, 1), 0.7, 6.0), blood=0.25, bump=0.35),
	"strangler": dict(body="basic", atlas="atlas_basic.png", swap={"769751": "7f8fa2", "3f5363": "1d1d22", "664531": "3a2a1c"}, vein=((0.25, 0.1, 0.32, 1), 0.8, 6.0), blood=0.5, bump=0.5),
	"spitter": dict(body="lis", atlas="atlas_people.png", swap={"c09264": "86b832", "bd8e30": "35461f", "466469": "23281d", "225385": "172214"}, vein=((0.1, 0.4, 0.04, 1), 0.9, 6.0), blood=0.3, bump=0.5),
	"sleeper": dict(body="lis", atlas="atlas_people.png", swap={"c09264": "ebe9f0", "bd8e30": "d9e2ec", "466469": "cdd5de", "225385": "d8d2c0"}, vein=((0.55, 0.28, 0.4, 1), 0.55, 8.0), blood=0.35, bump=0.3),
}


def V(*a):
	return Vector(a)


def hexc(h):
	return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def angle_diff(a, b):
	return (a - b + math.pi) % (2 * math.pi) - math.pi


class Build:
	def __init__(self, kind):
		self.kind = kind
		self.spec = SPEC[kind]
		bpy.ops.wm.read_factory_settings(use_empty=True)
		self.scene = bpy.context.scene
		bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, "zombie_%s.glb" % self.spec["body"]))
		self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
		self.body = bpy.data.objects["Body"]
		for o in list(bpy.data.objects):
			if o.type == "MESH" and o is not self.body:
				bpy.data.objects.remove(o, do_unlink=True)
		self.gear = []
		self.mats = {}
		self.rng = random.Random(sum(ord(c) * 31 ** i for i, c in enumerate(kind)) & 0xffff)
		zs = {n: self.arm.data.bones[n].head_local.z for n in ("Hips", "Abdomen", "Torso")}
		self.z_abd, self.z_tor = zs["Abdomen"], zs["Torso"]
		hid = self.body.vertex_groups["Head"].index
		hp = [v.co for v in self.body.data.vertices if any(x.group == hid and x.weight > 0.5 for x in v.groups) and v.co.z > 0.9]
		self.head = (min(p.x for p in hp), max(p.x for p in hp), min(p.y for p in hp), max(p.y for p in hp), min(p.z for p in hp), max(p.z for p in hp))

	# --- helpers ---
	def bone(self, name):
		b = self.arm.data.bones[name]
		return b.head_local.copy(), b.tail_local.copy()

	def trunk(self, co):
		return "Torso" if co.z > self.z_tor else "Abdomen" if co.z > self.z_abd else "Hips"

	def band(self, z0, z1, groups=("Torso", "Abdomen", "Hips", "Neck", "Shoulder.L", "Shoulder.R")):
		"""Centre and half extents of the skin between two heights."""
		z0 -= 0.07; z1 += 0.07
		idx = {g.index for g in self.body.vertex_groups if g.name in groups}
		pts = [v.co for v in self.body.data.vertices if z0 <= v.co.z <= z1 and any(x.group in idx and x.weight > 0.4 for x in v.groups) and abs(v.co.x) < 0.4]
		if not pts:
			pts = [v.co for v in self.body.data.vertices if z0 <= v.co.z <= z1 and abs(v.co.x) < 0.4]
		xs = [p.x for p in pts]; ys = [p.y for p in pts]
		return ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2)

	def limb_r(self, name, t0=0.0, t1=1.0):
		"""The skin's radius round bone [param name] between shares t0 and t1 of its length (verts weighted over half to it):
		the 75th percentile, since the largest caught the knee and calf bulges and a sleeve that wide gaped."""
		h, t = self.bone(name)
		d = t - h
		gi = self.body.vertex_groups[name].index
		found = []
		for v in self.body.data.vertices:
			if not any(x.group == gi and x.weight > 0.5 for x in v.groups):
				continue
			s = (v.co - h).dot(d) / d.length_squared
			if t0 <= s <= t1:
				found.append((v.co - (h + d * s)).length)
		return sorted(found)[int(len(found) * 0.75)] if found else 0.0

	def taper_tongue(self, shares=(0.95, 0.85, 0.7, 0.55, 0.4)):
		"""Draws the kit's capsule tongue to a point: each Tongue bone's skin pulled toward its axis, the more the nearer the tip."""
		for i, k in enumerate(shares):
			name = "Tongue%d" % (i + 1)
			if name not in self.body.vertex_groups:
				return
			h, t = self.bone(name)
			d = t - h
			gi = self.body.vertex_groups[name].index
			for v in self.body.data.vertices:
				w = max((x.weight for x in v.groups if x.group == gi), default=0.0)
				if w < 0.5:
					continue
				s = max(0.0, min(1.0, (v.co - h).dot(d) / max(d.length_squared, 1e-9)))
				axis = h + d * s
				f = k * (1.0 - 0.25 * s)
				v.co = axis + (v.co - axis) * f

	def mat(self, name, colour, rough=0.7, metal=0.0, blood=0.0, bump=0.0, bump_scale=40.0, veins=None):
		if name in self.mats:
			return self.mats[name]
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
		b.inputs["Base Color"].default_value = colour
		b.inputs["Roughness"].default_value = rough
		b.inputs["Metallic"].default_value = metal
		PARAMS[name] = ((blood, bump, bump_scale), veins)
		self.mats[name] = m
		return m

	def obj(self, name, bm, mat, bone):
		if isinstance(bm, bmesh.types.BMesh):
			me = bpy.data.meshes.new(name)
			bm.to_mesh(me); bm.free()
			o = bpy.data.objects.new(name, me)
			self.scene.collection.objects.link(o)
		else:
			o = bm
		o.data.materials.append(mat)
		for p in o.data.polygons:
			p.use_smooth = True
		groups = {}
		for v in o.data.vertices:
			b = bone(v.co) if callable(bone) else bone
			g = groups.get(b) or o.vertex_groups.new(name=b)
			groups[b] = g
			g.add([v.index], 1.0, "REPLACE")
		self.gear.append(o)
		return o

	def solid(self, o, t=0.006):
		m = o.modifiers.new("s", "SOLIDIFY"); m.thickness = t; m.offset = 1
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.modifier_apply(modifier="s")
		return o

	def bevel(self, o, w=0.003, seg=2):
		if w <= 0:
			return o
		m = o.modifiers.new("b", "BEVEL"); m.width = w; m.segments = seg; m.limit_method = "ANGLE"; m.angle_limit = math.radians(40)
		bpy.context.view_layer.objects.active = o
		bpy.ops.object.modifier_apply(modifier="b")
		return o


def ring(cx, cy, rx, ry, z, n=24, jit=0.0, rng=None, rot=0.0):
	pts = []
	for i in range(n):
		a = 2 * math.pi * i / n + rot
		pts.append(V(cx + rx * math.cos(a), cy + ry * math.sin(a), z + (rng.uniform(-jit, jit) if jit else 0.0)))
	return pts


def loft(rings, keep=None, cap_top=False):
	"""Quads between consecutive rings; keep(angle) false leaves a gap (an open front or back)."""
	bm = bmesh.new()
	vs = [[bm.verts.new(p) for p in r] for r in rings]
	n = len(rings[0])
	for k in range(len(rings) - 1):
		for i in range(n):
			j = (i + 1) % n
			a = 2 * math.pi * (i + 0.5) / n
			if keep is not None and not keep(a):
				continue
			try:
				bm.faces.new((vs[k][i], vs[k][j], vs[k + 1][j], vs[k + 1][i]))
			except ValueError:
				pass
	if cap_top:
		try:
			bm.faces.new(vs[0])
		except ValueError:
			pass
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def front(w):
	return lambda a: abs(angle_diff(a, -math.pi / 2)) < w


def not_front(w):
	return lambda a: abs(angle_diff(a, -math.pi / 2)) >= w


def not_back(w):
	return lambda a: abs(angle_diff(a, math.pi / 2)) >= w


def sleeve_rings(h, t, shares, radii, n=16, rng=None):
	"""Rings round the segment h-t at the given shares of its length and radii, for loft()."""
	d = (t - h).normalized()
	u = d.cross(V(0, 1, 0) if abs(d.y) < 0.9 else V(1, 0, 0)).normalized()
	w = d.cross(u)
	out = []
	for s, r in zip(shares, radii):
		c = h + (t - h) * s
		out.append([c + (u * math.cos(2 * math.pi * i / n) + w * math.sin(2 * math.pi * i / n)) * r * (1 + (rng.uniform(-0.04, 0.04) if rng else 0.0)) for i in range(n)])
	return out


def merge_bm(*bms):
	out = bmesh.new()
	for b in bms:
		me = bpy.data.meshes.new("t"); b.to_mesh(me); b.free()
		out.from_mesh(me)
		bpy.data.meshes.remove(me)
	return out


def xf(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
	bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=mathutils.Euler(rot).to_matrix())
	bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
	return bm


def box_bm(size, loc, rot=(0, 0, 0)):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	return xf(bm, loc, rot, size)


def sphere_bm(r, loc, scale=(1, 1, 1), u=14, v=8, cut_below=None):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=r)
	xf(bm, loc, (0, 0, 0), scale)
	if cut_below is not None:
		bmesh.ops.delete(bm, geom=[x for x in bm.verts if x.co.z < cut_below], context="VERTS")
	return bm


def spike_bm(base, d, length, r, n=8):
	d = Vector(d).normalized()
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=0.0, depth=length)
	q = V(0, 0, 1).rotation_difference(d)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=q.to_matrix())
	bmesh.ops.translate(bm, vec=Vector(base) + d * length / 2, verts=bm.verts)
	return bm


def tube_bm(a, b, r, n=8):
	a, b = Vector(a), Vector(b)
	d = b - a
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=r, depth=d.length)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=V(0, 0, 1).rotation_difference(d.normalized()).to_matrix())
	bmesh.ops.translate(bm, vec=(a + b) / 2, verts=bm.verts)
	return bm


def torus_bm(R, r, loc, rot=(0, 0, 0), scale=(1, 1, 1), nu=20, nv=6, turns=1.0, rise=0.0):
	"""A ring of tube; turns > 1 with a rise makes a coil."""
	bm = bmesh.new()
	steps = int(nu * turns)
	vs = []
	for i in range(steps + 1):
		a = 2 * math.pi * i / nu
		c = V(R * math.cos(a), R * math.sin(a), rise * i / nu)
		t = V(-math.sin(a), math.cos(a), 0).normalized()
		out = V(math.cos(a), math.sin(a), 0)
		ring_ = []
		for j in range(nv):
			b = 2 * math.pi * j / nv
			ring_.append(bm.verts.new(c + out * (r * math.cos(b)) + V(0, 0, 1) * (r * math.sin(b))))
		vs.append(ring_)
	for i in range(steps):
		for j in range(nv):
			k = (j + 1) % nv
			bm.faces.new((vs[i][j], vs[i][k], vs[i + 1][k], vs[i + 1][j]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return xf(bm, loc, rot, scale)


# --- the six kinds ------------------------------------------------------------------------------


def brute(b):
	IRON = b.mat("Iron", (0.34, 0.33, 0.35, 1), 0.5, 0.2, blood=0.55, bump=0.9, bump_scale=22)
	BAND = b.mat("Bandage", (0.66, 0.6, 0.48, 1), 0.9, blood=0.85, bump=0.5, bump_scale=70)
	BONE = b.mat("Horn", (0.78, 0.72, 0.58, 1), 0.6, blood=0.3, bump=0.5, bump_scale=30)
	LEATH = b.mat("Leather", (0.22, 0.13, 0.08, 1), 0.8, blood=0.4, bump=0.6, bump_scale=50)
	cx, cy, rx, ry = b.band(1.0, 1.27)
	for s, sx in (("L", 1), ("R", -1)):
		sh, _ = b.bone("UpperArm." + s)
		dome = sphere_bm(0.2, (sh.x + sx * 0.04, sh.y, sh.z + 0.02), (1.0, 0.95, 0.75), 16, 8, cut_below=sh.z + 0.0)
		b.bevel(b.solid(b.obj("pauldron" + s, dome, IRON, "Shoulder." + s), 0.014), 0.004)
		sp = [spike_bm((sh.x + sx * 0.05, sh.y, sh.z + 0.15), (sx * 0.35, 0, 1), 0.2, 0.04),
			spike_bm((sh.x + sx * 0.19, sh.y - 0.04, sh.z + 0.07), (sx * 1.0, -0.25, 0.5), 0.17, 0.035),
			spike_bm((sh.x + sx * 0.17, sh.y + 0.08, sh.z + 0.07), (sx * 0.8, 0.5, 0.5), 0.15, 0.035)]
		b.obj("pspikes" + s, merge_bm(*sp), IRON, "Shoulder." + s)
		lh, lt = b.bone("LowerArm." + s)
		wrap = merge_bm(tube_bm(lh + (lt - lh) * 0.1, lh + (lt - lh) * 0.9, 0.085, 10), sphere_bm(0.115, lt + V(sx * 0.01, 0, 0), (1, 1, 1.05), 12, 8))
		b.bevel(b.obj("fist" + s, wrap, BAND, "LowerArm." + s), 0.004)
	rings = [ring(cx, cy, rx + 0.035, ry + 0.035, z, 24) for z in (1.0, 1.1, 1.2, 1.28)]
	plate = b.solid(b.obj("chest", loft(rings, keep=front(1.05)), IRON, "Torso"), 0.016)
	b.bevel(plate, 0.004)
	rivets = [sphere_bm(0.016, (cx + dx, cy - ry - 0.05, z), u=8, v=5) for dx in (-0.1, 0.1) for z in (1.04, 1.24)]
	b.obj("rivets", merge_bm(*rivets), IRON, "Torso")
	ridge = [spike_bm((cx + (0.0 if i % 2 == 0 else 0.07 * (1 if i % 4 == 1 else -1)), cy + ry + 0.01, 0.95 + 0.07 * i), (0, 1, 0.55), 0.13 - 0.01 * i, 0.04) for i in range(6)]
	b.bevel(b.obj("spine", merge_bm(*ridge), BONE, lambda co: b.trunk(co)), 0.0)
	cx2, cy2, rx2, ry2 = b.band(0.84, 0.94)
	belt = b.solid(b.obj("belt", loft([ring(cx2, cy2, rx2 + 0.04, ry2 + 0.04, 0.86, 24), ring(cx2, cy2, rx2 + 0.045, ry2 + 0.045, 0.95, 24)]), LEATH, "Hips"), 0.012)
	b.bevel(belt, 0.003)
	b.bevel(b.obj("buckle", merge_bm(box_bm((0.13, 0.03, 0.1), (cx2, cy2 - ry2 - 0.06, 0.905)), *[box_bm((0.07, 0.012, 0.28), (cx2 + dx, cy2 - ry2 - 0.045, 0.72), (0, 0, 0.0)) for dx in (-0.1, 0.1)]), IRON, "Hips"), 0.004)
	hx0, hx1, hy0, hy1, hz0, hz1 = b.head
	hcx, hcy = (hx0 + hx1) / 2, (hy0 + hy1) / 2
	horns = [spike_bm((hcx + sx * 0.06, hcy, hz1 - 0.03), (sx * 0.9, -0.1, 0.6), 0.2, 0.034) for sx in (-1, 1)]
	b.obj("horns", merge_bm(*horns), BONE, "Head")


def bloater(b):
	FLESH = b.mat("BloatFlesh", (0.74, 0.72, 0.34, 1), 0.55, blood=0.35, bump=0.6, bump_scale=30, veins=((0.42, 0.5, 0.08, 1), 0.9, 6.0))
	BOIL = b.mat("Boil", (0.9, 0.84, 0.32, 1), 0.3, blood=0.2, bump=0.4, bump_scale=60, veins=((0.9, 0.5, 0.2, 1), 0.7, 14.0))
	RAW = b.mat("RawBoil", (0.62, 0.14, 0.1, 1), 0.3, blood=0.4, bump=0.5, bump_scale=60)
	RAG = b.mat("Rag", (0.28, 0.22, 0.14, 1), 0.95, blood=0.5, bump=0.8, bump_scale=60)
	cx, cy, rx, ry = b.band(0.87, 1.07)
	belly_c = (cx, cy - ry * 0.4, 0.96)
	srx, sry, srz = rx * 1.18, ry * 1.4, 0.22
	b.obj("belly", sphere_bm(1.0, belly_c, (srx, sry, srz), 20, 12), FLESH, "Abdomen")
	for i in range(18):
		a = b.rng.uniform(-math.pi * 0.95, -math.pi * 0.05) if i < 15 else b.rng.uniform(0.2, math.pi - 0.2)
		z = b.rng.uniform(-0.45, 0.85)
		k = math.sqrt(max(0.0, 1 - z * z))
		pos = V(belly_c[0] + srx * k * math.cos(a), belly_c[1] + sry * k * math.sin(a), belly_c[2] + srz * z * 1.0)
		r = b.rng.uniform(0.028, 0.065)
		d = V(math.cos(a) * k / srx, math.sin(a) * k / sry, z / srz).normalized()
		pos = pos + d * (r * 0.4)
		b.obj("boil%d" % i, sphere_bm(r, pos, (1, 1, 0.8), 10, 6), RAW if i % 4 == 3 else BOIL, b.trunk(pos))
	nh, nt = b.bone("Neck")
	b.obj("goitre", sphere_bm(0.085, (0, nh.y - 0.06, nh.z + 0.02), (1.15, 0.95, 1.0), 12, 8), BOIL, "Neck")
	for sx in (-1, 1):
		sh, _ = b.bone("UpperArm." + ("L" if sx > 0 else "R"))
		b.obj("shoulderboil%d" % sx, sphere_bm(0.05, (sh.x + sx * 0.04, sh.y + 0.03, sh.z + 0.06), (1, 1, 0.8), 10, 6), BOIL, "Shoulder." + ("L" if sx > 0 else "R"))
	cx2, cy2, rx2, ry2 = b.band(0.55, 0.85)
	# A belt round the hips, then four flaps hung from it, each lower edge carried by its own thigh: one tube
	# weighted to the hips was walked through by the thighs.
	b.solid(b.obj("ragbelt", loft([ring(cx2, cy2, rx2 + 0.025, ry2 + 0.025, z, 24) for z in (0.86, 0.8)]), RAG, "Hips"), 0.01)
	for s, sx in (("L", 1), ("R", -1)):
		for mid in (-math.pi / 2, math.pi / 2):
			lo, hi = (mid, mid + sx * 0.95) if sx * math.cos(mid + sx * 0.5) > 0 else (mid - sx * 0.95, mid)
			lo, hi = min(lo, hi), max(lo, hi)
			keep = lambda a, lo=lo, hi=hi: abs(angle_diff(a, (lo + hi) / 2)) < (hi - lo) / 2
			flap = loft([ring(cx2, cy2, rx2 + 0.03, ry2 + 0.035, 0.81, 24), ring(cx2, cy2, rx2 + 0.06, ry2 + 0.07, 0.6, 24, 0.04, b.rng)], keep=keep)
			bmesh.ops.delete(flap, geom=[v for v in flap.verts if not v.link_faces], context="VERTS")
			b.bevel(b.solid(b.obj("rag%s%d" % (s, mid > 0), flap, RAG, lambda co, s=s: "Hips" if co.z > 0.74 else "UpperLeg." + s), 0.008), 0.002)
	b.taper_tongue()


def strangler(b):
	CLOAK = b.mat("Cloak", (0.1, 0.1, 0.12, 1), 0.95, blood=0.5, bump=0.9, bump_scale=45)
	ROPE = b.mat("Rope", (0.5, 0.38, 0.2, 1), 0.9, blood=0.3, bump=1.0, bump_scale=120)
	CLAW = b.mat("Claw", (0.82, 0.78, 0.66, 1), 0.5, blood=0.6, bump=0.4, bump_scale=60)
	levels = [(1.31, 0.0), (1.24, 0.02), (1.12, 0.05), (0.98, 0.09), (0.84, 0.13), (0.7, 0.18), (0.56, 0.23), (0.42, 0.28)]
	rings = []
	for z, flare in levels:
		cx, cy, rx, ry = b.band(z - 0.03, z + 0.03)
		last = z == levels[-1][0]
		rings.append(ring(cx, cy + 0.01 + flare * 0.35, rx + 0.04 + flare, ry + 0.045 + flare * 0.9, z, 24, 0.07 if last else 0.0, b.rng))
	b.bevel(b.solid(b.obj("cloak", loft(rings, keep=not_front(0.5)), CLOAK, lambda co: b.trunk(co)), 0.01), 0.002)
	hx0, hx1, hy0, hy1, hz0, hz1 = b.head
	hcx, hcy, hcz = (hx0 + hx1) / 2, (hy0 + hy1) / 2, (hz0 + hz1) / 2
	hood = sphere_bm(1.0, (hcx, hcy + 0.015, hcz + 0.01), ((hx1 - hx0) * 0.62, (hy1 - hy0) * 0.62, (hz1 - hz0) * 0.6), 18, 10)
	bmesh.ops.delete(hood, geom=[v for v in hood.verts if v.co.y < hcy - 0.01 and v.co.z < hcz + 0.04 or v.co.z < hcz - (hz1 - hz0) * 0.2], context="VERTS")
	b.bevel(b.solid(b.obj("hood", hood, CLOAK, "Head"), 0.008), 0.002)
	nh, nt = b.bone("Neck")
	nc = (nh + nt) / 2
	coil = torus_bm(0.07, 0.014, (0, nc.y, nh.z - 0.01), nu=18, nv=6, turns=2.4, rise=0.032)
	b.obj("coil", coil, ROPE, "Neck")
	hang = []
	pts = [V(0, nc.y - 0.075, nh.z), V(0.015, nc.y - 0.1, nh.z - 0.15), V(-0.01, nc.y - 0.11, nh.z - 0.3), V(0.02, nc.y - 0.105, nh.z - 0.45)]
	for p, q in zip(pts, pts[1:]):
		hang.append(tube_bm(p, q, 0.014, 6))
	hang.append(torus_bm(0.045, 0.012, (0.02, nc.y - 0.105, nh.z - 0.5), (math.pi / 2, 0, 0), nu=14, nv=6))
	b.obj("noose", merge_bm(*hang), ROPE, "Torso")
	for s in ("L", "R"):
		for f in ("Index3", "Middle3", "Pinky3"):
			h, t = b.bone("%s.%s" % (f, s))
			d = (t - h).normalized()
			b.obj("claw" + f + s, spike_bm(t - d * 0.01, d + V(0, 0, -0.15), 0.115, 0.014, 6), CLAW, "%s.%s" % (f, s))


def spitter(b):
	ACID = b.mat("Acid", (0.52, 0.88, 0.07, 1), 0.25, blood=0.15, bump=0.6, bump_scale=60, veins=((0.2, 0.5, 0.02, 1), 0.6, 10.0))
	SAC = b.mat("Sac", (0.6, 0.82, 0.22, 1), 0.3, blood=0.25, bump=0.7, bump_scale=40, veins=((0.25, 0.4, 0.05, 1), 0.8, 8.0))
	TANK = b.mat("Tank", (0.2, 0.24, 0.17, 1), 0.5, 0.15, blood=0.4, bump=0.7, bump_scale=30)
	nh, nt = b.bone("Neck")
	cx, cy, rx, ry = b.band(1.0, 1.25)
	b.obj("throat", sphere_bm(0.085, (0, nh.y - 0.075, nh.z + 0.025), (1.1, 0.95, 1.25), 14, 10), SAC, "Neck")
	for sx in (-1, 1):
		tx, ty = cx + sx * 0.08, cy + ry + 0.075
		b.bevel(b.obj("tank%d" % sx, merge_bm(sphere_bm(0.085, (tx, ty, 1.02), (1, 1, 1.45), 14, 10), tube_bm((tx, ty, 1.2), (tx, ty, 1.26), 0.03, 10)), TANK, "Torso"), 0.0)
		b.obj("pipe%d" % sx, merge_bm(tube_bm((tx, ty, 1.26), (cx + sx * 0.05, ty - 0.02, 1.34), 0.014, 6), tube_bm((cx + sx * 0.05, ty - 0.02, 1.34), (sx * 0.035, nh.y + 0.02, nh.z + 0.03), 0.014, 6)), TANK, "Torso")
		b.obj("glow%d" % sx, sphere_bm(0.06, (tx, ty + 0.025, 1.0), (1, 0.8, 1.35), 12, 8), ACID, "Torso")
		s = "L" if sx > 0 else "R"
		lh, lt = b.bone("LowerArm." + s)
		for k, t in enumerate((0.25, 0.5, 0.78)):
			p = lh + (lt - lh) * t
			b.obj("abl%s%d" % (s, k), sphere_bm(0.04 - 0.005 * k, (p.x, p.y - 0.03, p.z + 0.03), (1, 1, 0.85), 10, 6), ACID, "LowerArm." + s)
	hx0, hx1, hy0, hy1, hz0, hz1 = b.head
	drips = [spike_bm((x, hy0 + 0.012, hz0 + 0.045), (0, -0.05, -1), l, 0.011, 6) for x, l in ((-0.03, 0.07), (0.0, 0.11), (0.032, 0.06))]
	b.obj("drips", merge_bm(*drips), ACID, "Head")


def sleeper(b):
	GOWN = b.mat("Gown", (0.74, 0.84, 0.92, 1), 0.92, blood=0.85, bump=0.6, bump_scale=60)
	WRAP = b.mat("Wrap", (0.88, 0.85, 0.76, 1), 0.9, blood=0.9, bump=0.8, bump_scale=70)
	TAG = b.mat("Tag", (0.9, 0.92, 0.95, 1), 0.5, blood=0.3, bump=0.2, bump_scale=60)
	levels = [(1.29, 0.0), (1.2, 0.0), (1.08, 0.01), (0.94, 0.03), (0.8, 0.06), (0.66, 0.09), (0.52, 0.12)]
	rings = []
	for z, flare in levels:
		cx, cy, rx, ry = b.band(z - 0.03, z + 0.03)
		rings.append(ring(cx, cy, rx + 0.03 + flare, ry + 0.035 + flare, z, 24, 0.035 if z == levels[-1][0] else 0.0, b.rng))
	b.bevel(b.solid(b.obj("gown", loft(rings), GOWN, lambda co: b.trunk(co)), 0.006), 0.002)
	for s, sx in (("L", 1), ("R", -1)):
		uh, ut = b.bone("UpperArm." + s)
		b.obj("sleeve" + s, tube_bm(uh - V(sx * 0.02, 0, 0), uh + (ut - uh) * 0.45, 0.075, 10), GOWN, "UpperArm." + s)
		lh, lt = b.bone("LowerArm." + s)
		# Bandaged forearms, round and closed, over the kit's flat ones; the hospital band over the wrist end.
		fr = max(b.limb_r("LowerArm." + s, 0.05, 0.95), 0.035) + 0.012
		b.bevel(b.obj("forearm" + s, merge_bm(tube_bm(lh + (lt - lh) * 0.04, lt - (lt - lh) * 0.02, fr, 12), sphere_bm(fr, lt - (lt - lh) * 0.02, (1, 1, 1), 12, 6)), WRAP, "LowerArm." + s), 0.002)
		b.bevel(b.obj("band" + s, tube_bm(lt - (lt - lh) * 0.22, lt - (lt - lh) * 0.1, fr + 0.008, 12), TAG, "LowerArm." + s), 0.0)
	hx0, hx1, hy0, hy1, hz0, hz1 = b.head
	hcx, hcy, hcz = (hx0 + hx1) / 2, (hy0 + hy1) / 2, (hz0 + hz1) / 2
	hw, hd, hh = hx1 - hx0, hy1 - hy0, hz1 - hz0
	# Bandages that hug the skull (a dome wider than the head and a brim read as a mushroom cap): a shell
	# 4% over the skull from the crown to the brow, then three cloth strips round it, each tilted differently.
	zc0, zr = hcz - hh * 0.08, hh * 0.6
	# Closed underneath: a shell cut at the jaw showed its black inside from behind and below.
	wrap = sphere_bm(1.0, (hcx, hcy + 0.004, zc0), (hw * 0.56, hd * 0.56, zr * 1.05), 18, 10)

	def skull_ring(z, lean):
		f = max(0.2, 1.0 - ((z - zc0) / zr) ** 2) ** 0.5
		return ring(hcx, hcy + 0.004 + lean, hw * 0.56 * f + 0.012, hd * 0.53 * f + 0.012, z, 18)
	strips = [loft([skull_ring(hcz + hh * (zc + k * 0.06), tilt * k) for k in (-1, 0, 1)]) for zc, tilt in ((-0.1, 0.012), (0.06, -0.014), (0.22, 0.01))]
	b.bevel(b.solid(b.obj("headwrap", merge_bm(wrap, *strips), WRAP, "Head"), 0.006), 0.002)
	cx, cy, rx, ry = b.band(1.2, 1.3)
	b.obj("tie", merge_bm(*[box_bm((0.012, 0.01, 0.1), (cx + dx, cy + ry + 0.04, 1.2), (0, 0.2 * dx / abs(dx), 0)) for dx in (-0.03, 0.03)]), TAG, "Torso")


def screamer(b):
	ROBE = b.mat("Robe", (0.34, 0.06, 0.13, 1), 0.9, blood=0.65, bump=0.8, bump_scale=50)
	BONE = b.mat("Crest", (0.82, 0.8, 0.7, 1), 0.55, blood=0.2, bump=0.5, bump_scale=40)
	cx, cy, rx, ry = b.band(1.0, 1.27)
	bodice = loft([ring(cx, cy, rx + 0.02, ry + 0.025, z, 24) for z in (0.96, 1.06, 1.16, 1.26)])
	b.bevel(b.solid(b.obj("bodice", bodice, ROBE, lambda co: b.trunk(co)), 0.008), 0.002)
	# A short peplum over trousers: a cone robe to the floor had no legs, and the legs poked through it in the walk.
	levels = [(0.95, 0.0), (0.82, 0.04), (0.7, 0.08)]
	rings = []
	for z, flare in levels:
		cx2, cy2, rx2, ry2 = b.band(max(z - 0.03, 0.56), max(z + 0.03, 0.62), ("Hips", "Abdomen", "UpperLeg.L", "UpperLeg.R"))
		rings.append(ring(cx2, cy2 + 0.01, rx2 + 0.06 + flare, ry2 + 0.07 + flare, z, 28, 0.05 if z == levels[-1][0] else 0.0, b.rng))
	b.bevel(b.solid(b.obj("skirt", loft(rings), ROBE, "Hips"), 0.01), 0.002)
	hx0, hx1, hy0, hy1, hz0, hz1 = b.head
	hcx, hcy, hcz = (hx0 + hx1) / 2, (hy0 + hy1) / 2, (hz0 + hz1) / 2
	crest = [spike_bm((hcx + (i % 2 - 0.5) * 0.04, hcy - 0.03 + 0.03 * i, hz1 - 0.01 - 0.008 * i), (0, 0.5 + 0.1 * i, 1), 0.2 - 0.018 * i, 0.03) for i in range(6)]
	b.obj("crest", merge_bm(*crest), BONE, "Head")
	CLOTH = b.mat("Trouser", (0.16, 0.05, 0.08, 1), 0.92, blood=0.55, bump=0.8, bump_scale=60)
	for s in ("L", "R"):
		for bone_name, t0, t1 in (("UpperLeg." + s, -0.02, 1.08), ("LowerLeg." + s, -0.04, 0.86)):
			h, t = b.bone(bone_name)
			# Rings fitted to the skin along the bone, so the cloth follows the leg's taper instead of a barrel round it.
			shares = [t0 + (t1 - t0) * k / 5 for k in range(6)]
			radii = [max(b.limb_r(bone_name, s - 0.15, s + 0.15), 0.035) + 0.012 for s in shares]
			b.bevel(b.solid(b.obj("trouser%s%s" % (bone_name[:5], s), loft(sleeve_rings(h, t, shares, radii, 16, b.rng)), CLOTH, bone_name), 0.006), 0.002)
	b.taper_tongue()
	for s, sx in (("L", 1), ("R", -1)):
		sh, _ = b.bone("UpperArm." + s)
		b.obj("spur" + s, merge_bm(spike_bm((sh.x, sh.y, sh.z + 0.03), (sx, 0.1, 0.5), 0.2, 0.035), spike_bm((sh.x, sh.y, sh.z + 0.03), (sx * 0.3, 0.1, 1), 0.13, 0.03)), BONE, "Shoulder." + s)


MAKERS = {"brute": brute, "bloater": bloater, "strangler": strangler, "spitter": spitter, "sleeper": sleeper, "screamer": screamer}


# --- paint, bake, export ------------------------------------------------------------------------


def recolour(img, swap, tol=0.06):
	"""The kit atlas with each of the kind's swatches replaced; returns how many pixels changed."""
	px = list(img.pixels)
	pairs = [(hexc(a), hexc(c)) for a, c in swap.items()]
	n = 0
	for i in range(0, len(px), 4):
		r, g, bl = px[i], px[i + 1], px[i + 2]
		for f, t in pairs:
			if abs(r - f[0]) < tol and abs(g - f[1]) < tol and abs(bl - f[2]) < tol:
				# keep the swatch's shading: the kit's atlas has light and dark tones of each colour
				px[i], px[i + 1], px[i + 2] = t
				n += 1
				break
	img.pixels = px
	return n


def grime(m):
	"""Dirt, edge wear, blood, veins and a bump on the material's base colour (all procedural)."""
	(blood, bump, bump_scale), veins = PARAMS[m.name]
	nt = m.node_tree
	bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	src = bs.inputs["Base Color"]
	base_link = src.links[0].from_socket if src.links else None
	base_val = tuple(src.default_value)
	l = nt.links
	co = nt.nodes.new("ShaderNodeTexCoord")

	def node(kind, **kw):
		n = nt.nodes.new(kind)
		for k, v in kw.items():
			setattr(n, k, v)
		return n

	def ramp(a, b_, ca, cb):
		r = nt.nodes.new("ShaderNodeValToRGB")
		r.color_ramp.elements[0].position = a; r.color_ramp.elements[1].position = b_
		r.color_ramp.elements[0].color = ca; r.color_ramp.elements[1].color = cb
		return r

	def mulmix(a_sock, b_sock, fac=1.0):
		mx = node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
		mx.inputs["Factor"].default_value = fac
		if isinstance(a_sock, tuple):
			mx.inputs["A"].default_value = a_sock
		else:
			l.new(a_sock, mx.inputs["A"])
		l.new(b_sock, mx.inputs["B"])
		return mx.outputs["Result"]

	n1 = node("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 9; n1.inputs["Detail"].default_value = 9
	n2 = node("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 60; n2.inputs["Detail"].default_value = 3
	vor = node("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 14
	l.new(co.outputs["Object"], n1.inputs["Vector"]); l.new(co.outputs["Object"], n2.inputs["Vector"]); l.new(co.outputs["Object"], vor.inputs["Vector"])
	dirt = ramp(0.38, 0.62, (0.5, 0.45, 0.38, 1), (1, 1, 1, 1)); l.new(n1.outputs["Fac"], dirt.inputs["Fac"])
	fine = ramp(0.4, 0.55, (0.84, 0.84, 0.84, 1), (1, 1, 1, 1)); l.new(n2.outputs["Fac"], fine.inputs["Fac"])
	splash = ramp(0.1, 0.18, (0.36, 0.03, 0.02, 1), (1, 1, 1, 1)); l.new(vor.outputs["Distance"], splash.inputs["Fac"])
	geo = node("ShaderNodeNewGeometry")
	edge = ramp(0.42, 0.55, (0.74, 0.66, 0.54, 1), (1, 1, 1, 1)); l.new(geo.outputs["Pointiness"], edge.inputs["Fac"])
	cur = base_link if base_link else base_val
	cur = mulmix(cur, dirt.outputs["Color"])
	cur = mulmix(cur, fine.outputs["Color"])
	cur = mulmix(cur, edge.outputs["Color"])
	if veins:
		vc, va, vs = veins
		vv = node("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE"); vv.inputs["Scale"].default_value = vs
		w = node("ShaderNodeTexNoise"); w.inputs["Scale"].default_value = 3; w.inputs["Detail"].default_value = 2
		add = node("ShaderNodeVectorMath", operation="ADD")
		sc = node("ShaderNodeVectorMath", operation="SCALE"); sc.inputs["Scale"].default_value = 0.35
		l.new(w.outputs["Color"], sc.inputs[0]); l.new(co.outputs["Object"], add.inputs[0]); l.new(sc.outputs["Vector"], add.inputs[1])
		l.new(co.outputs["Object"], w.inputs["Vector"])
		l.new(add.outputs["Vector"], vv.inputs["Vector"])
		vr = ramp(0.0, 0.05, vc, (1, 1, 1, 1)); l.new(vv.outputs["Distance"], vr.inputs["Fac"])
		cur = mulmix(cur, vr.outputs["Color"], va)
	cur = mulmix(cur, splash.outputs["Color"], blood)
	l.new(cur, src)
	if bump > 0:
		bn = node("ShaderNodeBump"); bn.inputs["Strength"].default_value = min(bump, 1.0); bn.inputs["Distance"].default_value = 0.01
		nz = node("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = bump_scale; nz.inputs["Detail"].default_value = 8
		l.new(co.outputs["Object"], nz.inputs["Vector"]); l.new(nz.outputs["Fac"], bn.inputs["Height"]); l.new(bn.outputs["Normal"], bs.inputs["Normal"])


def finish(b):
	scene, arm, body, gear, spec, kind = b.scene, b.arm, b.body, b.gear, b.spec, b.kind
	atlas = bpy.data.images.load(os.path.join(KIT, spec["atlas"]))
	print("RECOLOUR", kind, recolour(atlas, spec["swap"]), "pixels")
	atlas.pack()
	skin = b.mat("Skin", (0.5, 0.6, 0.4, 1), 0.7, blood=spec["blood"], bump=spec["bump"], bump_scale=70, veins=spec["vein"])
	nt = skin.node_tree
	tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = atlas; tex.interpolation = "Closest"
	uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "UVMap"
	nt.links.new(uvn.outputs["UV"], tex.inputs["Vector"])
	nt.links.new(tex.outputs["Color"], next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"])
	body.data.materials.clear()
	body.data.materials.append(skin)
	for m in list(b.mats.values()):
		grime(m)
	for g in gear:
		g.parent = arm
		mod = g.modifiers.new("Armature", "ARMATURE"); mod.object = arm
	allo = [body] + gear
	bpy.ops.object.select_all(action="DESELECT")
	for o in allo:
		o.select_set(True)
		if "Bake" not in o.data.uv_layers:
			o.data.uv_layers.new(name="Bake")
		o.data.uv_layers["Bake"].active = True
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
	bpy.ops.uv.pack_islands(margin=0.003)
	bpy.ops.object.mode_set(mode="OBJECT")
	for o in allo:
		o.data.uv_layers["Bake"].active_render = True

	img = bpy.data.images.new("%s_albedo" % kind, BAKE, BAKE)
	ao = bpy.data.images.new("%s_ao" % kind, BAKE, BAKE)
	nrm = bpy.data.images.new("%s_normal" % kind, BAKE, BAKE)
	nrm.colorspace_settings.name = "Non-Color"
	targets = {}
	for o in allo:
		for m in o.data.materials:
			targets[(o.name, m.name)] = m.node_tree.nodes.new("ShaderNodeTexImage")
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 24
	try:
		p = bpy.context.preferences.addons["cycles"].preferences
		p.compute_device_type = "OPTIX"; p.get_devices()
		for d in p.devices:
			d.use = True
		scene.cycles.device = "GPU"
	except Exception as e:
		print("no GPU", e)

	def set_target(image):
		for (_, mn), tn in targets.items():
			tn.image = image
		for o in allo:
			for m in o.data.materials:
				m.node_tree.nodes.active = next(n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image == image)

	bpy.ops.object.select_all(action="DESELECT")
	for o in allo:
		o.select_set(True)
	bpy.context.view_layer.objects.active = body
	r = scene.render.bake
	r.use_pass_direct = False; r.use_pass_indirect = False; r.use_pass_color = True; r.margin = 6
	set_target(img)
	bpy.ops.object.bake(type="DIFFUSE")
	set_target(ao)
	scene.cycles.samples = 96
	bpy.ops.object.bake(type="AO")
	r.normal_space = "TANGENT"
	set_target(nrm)
	scene.cycles.samples = 8
	bpy.ops.object.bake(type="NORMAL")
	px = list(img.pixels); pa = list(ao.pixels)
	for i in range(0, len(px), 4):
		k = 0.4 + 0.6 * pa[i]
		px[i] *= k; px[i + 1] *= k; px[i + 2] *= k
	img.pixels = px
	for im in (img, nrm):
		im.filepath_raw = os.path.join(OUT, im.name + ".png")
		im.file_format = "PNG"
		im.save()

	final = bpy.data.materials.new("Atlas")
	final.use_nodes = True
	fb = next(n for n in final.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	ti = final.node_tree.nodes.new("ShaderNodeTexImage"); ti.image = bpy.data.images.load(img.filepath_raw)
	tn_ = final.node_tree.nodes.new("ShaderNodeTexImage"); tn_.image = bpy.data.images.load(nrm.filepath_raw); tn_.image.colorspace_settings.name = "Non-Color"
	nm = final.node_tree.nodes.new("ShaderNodeNormalMap")
	final.node_tree.links.new(ti.outputs["Color"], fb.inputs["Base Color"])
	final.node_tree.links.new(tn_.outputs["Color"], nm.inputs["Color"])
	final.node_tree.links.new(nm.outputs["Normal"], fb.inputs["Normal"])
	fb.inputs["Roughness"].default_value = 0.75
	for o in gear:
		o.parent = None
		for mod in list(o.modifiers):
			if mod.type == "ARMATURE":
				o.modifiers.remove(mod)
	for o in allo:
		o.data.materials.clear()
		o.data.materials.append(final)
		if "UVMap" in o.data.uv_layers:
			o.data.uv_layers.remove(o.data.uv_layers["UVMap"])
	bpy.ops.object.select_all(action="DESELECT")
	for o in allo:
		o.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = "Body"
	print("SPECIAL", kind, "tris", sum(len(p.vertices) - 2 for p in body.data.polygons), "bones", len(arm.data.bones))

	for old in list(body.data.color_attributes):
		body.data.color_attributes.remove(old)
	attr = body.data.color_attributes.new("Wear", "BYTE_COLOR", "POINT")

	def n01(p, s, o):
		return max(0.0, min(1.0, 0.5 + 0.5 * mathutils.noise.noise(p * s + o)))

	for v in body.data.vertices:
		attr.data[v.index].color = (n01(v.co, 3.0, V(1.3, 7.1, 2.9)), n01(v.co, 4.5, V(9.2, 3.3, 5.7)), n01(v.co, 2.0, V(4.4, 8.8, 0.6)), 1.0)
	body.data.color_attributes.active_color = attr
	bm_ = bmesh.new(); bm_.from_mesh(body.data)
	bmesh.ops.triangulate(bm_, faces=bm_.faces[:])
	bm_.to_mesh(body.data); bm_.free()
	for a in list(bpy.data.actions):
		a.name = a.name.replace("_CharacterArmature", "")

	if SHEET:
		sheet(b, scene, arm)

	if arm.animation_data is None:
		arm.animation_data_create()
	arm.animation_data.action = None
	for t in list(arm.animation_data.nla_tracks):
		arm.animation_data.nla_tracks.remove(t)
	for a in bpy.data.actions:
		if a.name in CLIPS.values():
			tr = arm.animation_data.nla_tracks.new(); tr.name = a.name
			tr.strips.new(a.name, int(a.frame_range[0]), a)
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True); arm.select_set(True)
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "zombie_%s.glb" % kind), export_format="GLB", use_selection=True,
		export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True, export_vertex_color="ACTIVE",
		export_materials="EXPORT", export_animations=True, export_animation_mode="NLA_TRACKS",
		export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
	print("SPECIAL OK", kind)


def sheet(b, scene, arm):
	bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
	fl = bpy.context.object
	fm = bpy.data.materials.new("Floor"); fm.use_nodes = True
	fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.18, 0.18, 1)
	fl.data.materials.append(fm)
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
	cam.data.lens = 60
	s = bpy.data.lights.new("sun", "SUN"); s.energy = 3.5
	so = bpy.data.objects.new("sun", s); so.rotation_euler = (math.radians(50), 0, math.radians(-30)); scene.collection.objects.link(so)
	w = bpy.data.worlds.new("w"); w.use_nodes = True; scene.world = w
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.4, 0.45, 0.55, 1)
	scene.render.resolution_x = 600; scene.render.resolution_y = 800
	scene.cycles.samples = 40
	arm.animation_data_create()

	def shot(name, ang, dist=4.2, z=0.75):
		r = math.radians(ang)
		cam.location = (math.sin(r) * dist, -math.cos(r) * dist, z + 0.25)
		cam.rotation_euler = (Vector((0, 0, z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = os.path.join(OUT, "sheet_%s_%s.png" % (b.kind, name))
		bpy.ops.render.render(write_still=True)

	for nm, ang in (("front", 0), ("back", 180), ("quarter", 45)):
		shot(nm, ang)
	if "walk" in bpy.data.actions:
		arm.animation_data.action = bpy.data.actions["walk"]
		scene.frame_set(6)
		shot("walk", 40)
	arm.animation_data.action = None
	scene.frame_set(1)
	bpy.data.objects.remove(fl, do_unlink=True)


for kind in KINDS:
	b = Build(kind)
	MAKERS[kind](b)
	finish(b)
