extends Node

## The mounted-pack boot test's probe (tools/pack_boot_test.sh copies it into a host project built at the
## addons.lock tags). It mounts a publish dry-run's objects the way dot-cloud's mounter does (a .pck under
## res://dot_cloud/<id>/<version>/) and fails when anything a server boots from would not:
##   - a script the pack ships does not compile against the host's addons (a stale tree, an addon API drift);
##   - game.yml's module, scene or client_scene does not load;
##   - requires.json names an addon the host lacks, or a level above the one it carries.
## User args: OUT_DIR (holding manifest.json and objects/). Exit 0 clean, 1 failures (each printed), 2 usage.

var _bad := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("pack_boot: usage: -- OUT_DIR")
		get_tree().quit(2)
		return
	get_tree().quit(_run(args[0]))


func _run(out: String) -> int:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("manifest.json")))
	if not (manifest is Dictionary) or not (manifest as Dictionary).has("files"):
		printerr("pack_boot: no readable manifest.json in %s" % out)
		return 2
	var m := manifest as Dictionary
	var prefix := "res://%s/%s/%s" % [str(m.get("mount_root", "dot_cloud")), str(m["content_id"]), str(m["version"])]
	var pck := OS.get_temp_dir().path_join("pack_boot_%d.pck" % OS.get_process_id())
	var packer := PCKPacker.new()
	if packer.pck_start(pck) != OK:
		printerr("pack_boot: cannot write %s" % pck)
		return 2
	var scripts: PackedStringArray = []
	var by_path := {}
	for f: Dictionary in m["files"]:
		var sha := str(f["sha256"])
		var obj := out.path_join("objects").path_join(sha.substr(0, 2)).path_join(sha)
		if not FileAccess.file_exists(obj):
			_fail("%s: object %s is not in %s" % [f["path"], sha, out])
			continue
		var at := prefix.path_join(str(f["path"]))
		packer.add_file(at, obj)
		by_path[str(f["path"])] = obj
		if at.ends_with(".gd"):
			scripts.append(at)
	packer.flush()
	if not ProjectSettings.load_resource_pack(pck, false):
		printerr("pack_boot: the engine would not mount %s" % pck)
		return 2
	print("pack_boot: mounted %d files at %s" % [by_path.size(), prefix])

	_check_requires(by_path)

	for path in scripts:
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			_fail("%s does not compile against the host's addons" % path)

	var yml := FileAccess.get_file_as_string(str(by_path.get("game.yml", "")))
	for key in ["module", "scene", "client_scene"]:
		var rel := _yml_value(yml, key)
		if rel == "":
			continue
		var res: Resource = load(prefix.path_join(rel))
		if res == null or (res is GDScript and not (res as GDScript).can_instantiate()):
			_fail("game.yml %s (%s) does not load mounted" % [key, rel])
		else:
			print("pack_boot: game.yml %s loads: %s" % [key, rel])

	DirAccess.remove_absolute(pck)
	print("pack_boot: %d script(s) compiled, %d failure(s)" % [scripts.size(), _bad])
	return 1 if _bad > 0 else 0


func _check_requires(by_path: Dictionary) -> void:
	if not by_path.has("requires.json"):
		print("pack_boot: no requires.json in the pack")
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(by_path["requires.json"])))
	var addons: Dictionary = (doc as Dictionary).get("addons", {}) if doc is Dictionary else {}
	for name: String in addons:
		var dir := "res://addons/%s" % name
		if not DirAccess.dir_exists_absolute(dir):
			_fail("requires.json names %s, which the host does not carry" % name)
			continue
		var level := 1
		var api := FileAccess.get_file_as_string("%s/%s_api.gd" % [dir, name])
		var m := RegEx.create_from_string("(?m)^const LEVEL *:= *(\\d+)").search(api)
		if m != null:
			level = m.get_string(1).to_int()
		if int(addons[name]) > level:
			_fail("requires.json asks %s level %d; the host carries %d" % [name, int(addons[name]), level])


static func _yml_value(text: String, key: String) -> String:
	for line in text.split("\n"):
		if line.begins_with(key + ":"):
			return line.substr(key.length() + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


func _fail(text: String) -> void:
	_bad += 1
	printerr("pack_boot: FAIL %s" % text)
