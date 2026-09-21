extends RefCounted

const Access := preload("res://scripts/courtyard/carried_map_access.gd")
const MAP_TEX := preload("res://assets/ui/maps/courtyard-sketch-v1.png")

var page: VBoxContainer
var _panel: Control


func _init(panel: Control) -> void:
	_panel = panel
	page = VBoxContainer.new()
	page.name = "MapPage"
	page.visible = false

	var title := Label.new()
	title.name = "MapTitle"
	title.add_theme_font_size_override("font_size", 34)
	page.add_child(title)

	var drawing := TextureRect.new()
	drawing.name = "MapDrawing"
	drawing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawing.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(drawing)

	var caption := Label.new()
	caption.name = "MapCaption"
	caption.add_theme_font_size_override("font_size", 24)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(caption)

	var root_vbox: Node = _panel.get_node_or_null("Margin/RootVBox")
	if root_vbox == null:
		return
	root_vbox.add_child(page)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var footer: Node = root_vbox.get_node_or_null("Footer")
	if footer != null:
		root_vbox.move_child(page, footer.get_index())


func has_map() -> bool:
	var pocket: Node = _find_pocket()
	if pocket == null:
		return false
	var inventory: Node = _panel.get_node_or_null("/root/Inventory")
	if inventory == null:
		return false
	return not Access.find_carried_map(inventory, pocket).is_empty()


func refresh() -> void:
	var drawing: TextureRect = page.get_node("MapDrawing")
	var title: Label = page.get_node("MapTitle")
	var caption: Label = page.get_node("MapCaption")
	if not has_map():
		drawing.texture = null
		title.text = ""
		caption.text = ""
		page.visible = false
		return
	drawing.texture = MAP_TEX
	title.text = _panel._text("ITEM_COURTYARD_SKETCH_NAME")
	caption.text = _panel._text("MENU_MAP_CAPTION")


func _find_pocket() -> Node:
	var node: Node = _panel
	while node != null:
		var actors: Node = node.get_node_or_null("Actors")
		if actors != null:
			var player: Node = actors.get_node_or_null("Player")
			if player != null:
				var pocket: Node = player.get_node_or_null("PocketAccess")
				if pocket != null:
					return pocket
		node = node.get_parent()
	return null
