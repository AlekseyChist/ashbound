extends SceneTree
const Lanterns=preload("res://scripts/world/snow_city_lanterns.gd")
func _initialize()->void:
 var path={"test":[Vector2(0,0),Vector2(0,2),Vector2(0,5)]}
 var failures=[]
 var cases=[Vector2(1000,1001),Vector2(1000,1003),Vector2(1001.099,1003),Vector2(1001.101,1003),Vector2(1000,1005.5),Vector2(1000,1006.2),Vector2(1003,1003)]
 var expected=[true,true,true,false,true,false,false]
 for i in cases.size():
  if not Lanterns.stoop_conflicts(cases[i],path).is_empty()!=expected[i]:failures.append(i)
 if not Lanterns.stoop_conflicts(Vector2(1000,1000),{}).is_empty():failures.append(7)
 print("STOOP_GUARD_TEST_DONE checks=8 failures=",failures)
 quit(0 if failures.is_empty() else 1)
