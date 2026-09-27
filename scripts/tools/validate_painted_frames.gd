extends SceneTree
## Independent QA of paired atlases: no production-builder helpers are called.
var failures: Array[String] = []
var images: Dictionary = {}
var measured: Dictionary = {}
var frame_entries := 0
var max_height_drift := 0.0
var max_head_width_drift := 0
var max_leg_width_drift := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
		printerr("PAINTED_FRAMES_FAIL: " + why)

func metrics(atlas: AtlasTexture, reference: Dictionary = {}) -> Dictionary:
	var path := atlas.atlas.resource_path
	if not images.has(path):
		var decoded := atlas.atlas.get_image()
		if decoded.is_compressed():
			check(decoded.decompress() == OK, "decode reference artwork " + path)
		images[path] = decoded
	var picture: Image = images[path]
	var box := Rect2i(atlas.region)
	var top := box.end.y
	var bottom := box.position.y
	var count := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if picture.get_pixel(x,y).a > 0.25:
				top = mini(top,y)
				bottom = maxi(bottom,y)
				count += 1
	var head_sum := 0.0
	var head_n := 0
	var head_left := box.end.x
	var head_right := box.position.x
	# Sample both variants at the same virtual-canvas height. A tighter atlas
	# crop must not move the measuring band down the head. Two original front
	# cells contain a detached pixel fragment above the actual hairstyle.
	var virtual_top := float(top-box.position.y)+atlas.margin.position.y
	var head_y := float(reference.get("head_y",virtual_top+10.0))
	var head_start := roundi(head_y-atlas.margin.position.y)+box.position.y
	# A slightly different alpha threshold/band from the builder detects drift
	# without just repeating its centroid implementation.
	for y in range(maxi(head_start,box.position.y),mini(head_start+20,box.end.y)):
		for x in range(box.position.x,box.end.x):
			if picture.get_pixel(x,y).a > 0.5:
				head_sum += x-box.position.x+atlas.margin.position.x
				head_n += 1
				head_left = mini(head_left, x)
				head_right = maxi(head_right, x)
	# Lower legs are outside the backpack silhouette. Comparing the whole
	# silhouette width would incorrectly reject the volume of the bag itself.
	var leg_left := box.end.x
	var leg_right := box.position.x
	var leg_n := 0
	var height := bottom-top+1
	var leg_y0 := float(reference.get("leg_y0",virtual_top+int(height*0.72)))
	var leg_y1 := float(reference.get("leg_y1",virtual_top+int(height*0.93)))
	var leg_start := roundi(leg_y0-atlas.margin.position.y)+box.position.y
	var leg_end := roundi(leg_y1-atlas.margin.position.y)+box.position.y
	for y in range(maxi(leg_start,box.position.y), mini(leg_end,box.end.y)):
		for x in range(box.position.x, box.end.x):
			if picture.get_pixel(x,y).a > 0.5:
				leg_left = mini(leg_left, x)
				leg_right = maxi(leg_right, x)
				leg_n += 1
	check(count > 1000 and head_n > 50,"nonempty complete figure " + path)
	check(leg_n > 50, "visible lower-leg landmarks " + path)
	return {"height":height,"head":head_sum/maxi(head_n,1),"sole":bottom-box.position.y+atlas.margin.position.y,"head_width":head_right-head_left+1,"leg_width":leg_right-leg_left+1,"head_y":head_y,"leg_y0":leg_y0,"leg_y1":leg_y1}

func pair(bare_path: String, pack_path: String) -> void:
	var bare: SpriteFrames = load(bare_path)
	var pack: SpriteFrames = load(pack_path)
	check(bare != null and pack != null,"pair resources load")
	if bare == null or pack == null: return
	check(bare.get_animation_names()==pack.get_animation_names(),"clip and alias parity")
	for key in bare.get_meta_list():
		var same: bool = pack.has_meta(key) and pack.get_meta(key)==bare.get_meta(key)
		if pack.has_meta(key) and bare.get_meta(key) is float:
			same = is_equal_approx(float(pack.get_meta(key)),float(bare.get_meta(key)))
		check(same,"metadata preserved: "+str(key))
	for clip in bare.get_animation_names():
		check(bare.get_frame_count(clip)==pack.get_frame_count(clip),"frame count "+clip)
		check(bare.get_animation_speed(clip)==pack.get_animation_speed(clip),"speed "+clip)
		check(bare.get_animation_loop(clip)==pack.get_animation_loop(clip),"loop "+clip)
		for i in bare.get_frame_count(clip):
			frame_entries += 1
			var a: AtlasTexture = bare.get_frame_texture(clip,i)
			var b: AtlasTexture = pack.get_frame_texture(clip,i)
			var label := clip+"["+str(i)+"]"
			check(a != b and a.atlas != b.atlas,"separate full art " + label)
			check(b.atlas.resource_path.contains("/painted-backpack/"),"uses painted full character " + label)
			check(a.get_size()==b.get_size(),"virtual canvas " + label)
			check(a.filter_clip==b.filter_clip,"filter " + label)
			check(b.region.size.x+b.margin.position.x<=b.get_width() and b.region.size.y+b.margin.position.y<=b.get_height(),"fits canvas " + label)
			check(bare.get_frame_duration(clip,i)==pack.get_frame_duration(clip,i),"duration " + label)
			var source_key := a.atlas.resource_path+str(a.region)+str(a.margin)
			if measured.has(source_key): continue
			measured[source_key] = true
			var am := metrics(a)
			var bm := metrics(b,am)
			var drift: float = absf(float(am.height)-float(bm.height))
			max_height_drift = maxf(max_height_drift,drift)
			if drift>8.0 or absf(am.sole-bm.sole)>1.0:
				print("PAINTED_DIAGNOSTIC ",label," before=",a.region," after=",b.region," metrics=",am," / ",bm)
			check(drift<=8.0,"body height changed by "+str(drift)+"px " + label)
			check(absf(am.sole-bm.sole)<=1.0,"sole anchor " + label)
			check(absf(am.head-bm.head)<=2.5,"head/body horizontal alignment " + label+" delta="+str(am.head-bm.head))
			var head_drift := absi(int(am.head_width)-int(bm.head_width))
			var leg_drift := absi(int(am.leg_width)-int(bm.leg_width))
			if head_drift>3 or leg_drift>4:
				print("BODY_WIDTH_DIAGNOSTIC ",label," regions=",a.region," / ",b.region," metrics=",am," / ",bm)
			max_head_width_drift = maxi(max_head_width_drift, head_drift)
			max_leg_width_drift = maxi(max_leg_width_drift, leg_drift)
			check(head_drift<=3, "head width changed by "+str(head_drift)+"px " + label)
			check(leg_drift<=4, "lower-leg span changed by "+str(leg_drift)+"px " + label)

func run() -> void:
	pair("res://assets/characters/courtyard/traveler_frames.tres","res://assets/characters/courtyard/traveler_backpack_frames.tres")
	pair("res://assets/characters/courtyard/traveler_pocket_frames.tres","res://assets/characters/courtyard/traveler_backpack_pocket_frames.tres")
	check(measured.size()==84,"all 84 unique runtime poses measured; got "+str(measured.size()))
	print("ASHBOUND_PAINTED_FRAMES entries=",frame_entries," unique=",measured.size()," max_height_drift_px=",max_height_drift)
	print("ASHBOUND_BODY_WIDTH max_head_drift_px=",max_head_width_drift," max_leg_span_drift_px=",max_leg_width_drift)
	if failures.is_empty():
		print("ASHBOUND_PAINTED_FRAMES_OK")
		quit(0)
	else: quit(1)
