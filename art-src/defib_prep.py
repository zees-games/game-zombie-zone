"""Scales, centres and floors the downloaded defibrillator (see assets/defib/LICENSE-defibrillator.txt).
blender -b --factory-startup --python art-src/defib_prep.py -- source.glb assets/defib/defib.glb"""
import sys
import bpy
from mathutils import Vector

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.visible_get()]
for o in bpy.context.scene.objects:
    o.select_set(False)
root = bpy.data.objects.new("Defib", None)
bpy.context.scene.collection.objects.link(root)
for o in bpy.context.scene.objects:
    if o.parent is None and o is not root:
        o.parent = root
bpy.context.view_layer.update()
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
long_side = max(hi.x - lo.x, hi.y - lo.y)
s = 0.42 / long_side  # the unit is about as long as a medkit
root.scale = (s, s, s)
root.location = (-(lo.x + hi.x) * 0.5 * s, -(lo.y + hi.y) * 0.5 * s, -lo.z * s)
bpy.context.view_layer.update()
for o in meshes:
    o.select_set(True)
root.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_yup=True,
                          export_materials="EXPORT")
