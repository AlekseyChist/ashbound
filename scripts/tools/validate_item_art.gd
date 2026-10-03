extends SceneTree
## ITEM-ART-AUDIT-01: real item art must resolve in both UI and dropped-item consumers.
## The oracle is the viewed 3x3 sheet and assets/ui/inventory/PROMPTS.md, not either resolver.
const PANEL_SCENE := "res://scenes/courtyard/touch_inventory_panel.tscn"
const WORLD_ITEMS_SCRIPT := "res://scripts/courtyard/courtyard_world_items.gd"
const ATLAS := "res://assets/ui/inventory/items-v1.png"
const MAP := "res://assets/ui/maps/courtyard-sketch-v1.png"
const EXPECTED_CELLS := {
	"rusty_sword": Vector2i(0, 0), "iron_sword": Vector2i(1, 0), "cultist_blade": Vector2i(2, 0),
	"leather_armor": Vector2i(0, 1), "chain_mail": Vector2i(1, 1), "bread": Vector2i(2, 1),
	"health_potion": Vector2i(0, 2), "stamina_potion": Vector2i(1, 2), "sacred_ash": Vector2i(2, 2),
}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ITEM_ART_FAIL " + label)

func has_cutout_pixels(source: Image, region: Rect2i) -> bool:
	var visible := 0
	var clear := 0
	for y in range(region.position.y, region.end.y, 4):
		for x in range(region.position.x, region.end.x, 4):
			var alpha := source.get_pixel(x, y).a
			if alpha > 0.5: visible += 1
			if alpha < 0.01: clear += 1
	return visible > 16 and clear > 16

func run() -> void:
	await process_frame # Autoloads must exist before compiling their dependent scripts.
	var source := Image.new()
	var decode_error := source.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS))
	check(decode_error == OK and not source.is_empty(), "source sheet can be decoded")
	if decode_error != OK or source.is_empty():
		finish()
		return
	check(source.get_width() == source.get_height(), "square sheet fits its documented 3x3 grid")
	var cell_size := Vector2(source.get_size()) / 3.0
	var world_items: GDScript = load(WORLD_ITEMS_SCRIPT)
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate()
	root.add_child(panel)
	await process_frame # Exercise the real _ready path; do not seed its private texture field.
	var catalog: ItemCatalog = load("res://data/items/catalog.tres")
	var seen := {}
	for item in catalog.items:
		seen[item.id] = true
		var ui: Texture2D = panel._item_texture(item.id)
		var dropped: Texture2D = world_items.texture_for_item(item.id)
		check(ui != null and dropped != null, "%s resolves in UI and on ground" % item.id)
		if ui == null or dropped == null:
			continue
		if item.id == "courtyard_sketch":
			check(ui.resource_path == MAP and dropped.resource_path == MAP, "map uses its complete separate drawing")
			continue
		check(EXPECTED_CELLS.has(item.id), "%s has a reviewed source drawing" % item.id)
		if not EXPECTED_CELLS.has(item.id):
			continue
		check(ui is AtlasTexture and dropped is AtlasTexture, "%s reuses the sheet without new artwork" % item.id)
		if not (ui is AtlasTexture and dropped is AtlasTexture):
			continue
		var expected := Rect2(Vector2(EXPECTED_CELLS[item.id]) * cell_size, cell_size)
		check(ui.atlas.resource_path == ATLAS and dropped.atlas.resource_path == ATLAS
			and ui.region.is_equal_approx(expected) and dropped.region.is_equal_approx(expected)
			and ui.filter_clip and dropped.filter_clip, "%s shows the correct bounded drawing in both consumers" % item.id)
		check(has_cutout_pixels(source, Rect2i(expected)), "%s source region contains visible art and transparency" % item.id)
		print("ITEM_ART_SOURCE id=", item.id, " region=", expected)
	check(seen.size() == 10 and seen.has("courtyard_sketch"), "all ten current catalog items inspected")
	for id in EXPECTED_CELLS:
		check(seen.has(id), "catalog includes " + id)
	for unknown in ["", "__unknown_item_art__"]:
		check(panel._item_texture(unknown) == null and world_items.texture_for_item(unknown) == null,
			"unrecognized ID does not borrow another item's drawing: " + unknown)
	var sword: ItemData = load("res://data/items/rusty_sword.tres")
	print("ITEM_ART_LEGACY_METADATA path=", sword.icon, " exists=", ResourceLoader.exists(sword.icon))
	panel.queue_free()
	await process_frame
	await process_frame
	finish()

func finish() -> void:
	print("ITEM_ART_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
