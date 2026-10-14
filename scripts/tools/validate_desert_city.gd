extends SceneTree
const City=preload("res://scripts/world/world_desert_city.gd")
class Lots extends RefCounted:
    func level_of(_code: String, city := "snow") -> float:return 83.5 if city=="desert" else NAN
class World extends Node3D:
    var snow_lots=Lots.new()
    var player: CharacterBody3D
var failures:=[]
var checks:=0
func check(ok:bool,label:String)->void:
    checks+=1
    if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
    var w=World.new();root.add_child(w)
    var city=City.new();root.add_child(city)
    check(city.build(w),"real scene build")
    await process_frame
    check(city.placed.size()==30 and city.unresolved.size()==13,"real30/13")
    var model_counts=[]
    for item in city.placed:
        var model:Node3D=item.node
        var portals=[]
        for door in city.get_doors():
            if model.is_ancestor_of(door):portals.append(door)
        check(portals.size()>0,"door registered "+item.code)
        check(not model.find_children("*","CollisionShape3D",true,false).is_empty(),"physics imported "+item.code)
        check(model.has_method("set_interior_visible"),"visibility API "+item.code)
        check(model.scale==Vector3.ONE and is_equal_approx(model.position.y,83.5),"native authored floor "+item.code)
        model_counts.append({"code":item.code,"doors":portals.size(),"lights":model.find_children("*","OmniLight3D",true,false).size()})
    city.set_lighting_enabled(false)
    for item in city.placed:
        for light in item.node.find_children("*","OmniLight3D",true,false):check(not light.visible,"lights off "+item.code)
    city.set_lighting_enabled(true)
    w.player=CharacterBody3D.new();w.add_child(w.player)
    await physics_frame
    for item in city.placed:
        w.player.global_position=item.node.to_global(Vector3(0,0,0))
        city._process(.5)
        check(item.node.interior_visible,"occupied visible "+item.code)
    city.clear_door_highlights()
    var doors=city.get_doors();doors.clear()
    check(not city.get_doors().is_empty(),"door array defensive copy")
    DirAccess.make_dir_recursive_absolute("res://local/qa/desert-city-builder")
    var f=FileAccess.open("res://local/qa/desert-city-builder/real-result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"placed":city.placed.size(),"unresolved":city.unresolved.size(),"doors":city.get_doors().size(),"models":model_counts,"scope":"Real8family imports and runtime API on flat83.5fixture; no terrain route/render/FPS/mobile acceptance"},"  "));f.close()
    print("DESERT_REAL_RESOURCES_DONE checks=",checks," failures=",failures.size()," doors=",city.get_doors().size())
    quit(0 if failures.is_empty() else 1)
