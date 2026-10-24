extends SceneTree
## Stable gem test entry for the four-slot v4 draw/equip/reforge/salvage system.
const OUT = "res://build/qa/gem-v3-implementation-20261022/gems/"
func _initialize(): call_deferred("run")
func run():
 var economy = preload("res://tests/gem_v3_economy_tests.gd").new()
 economy.run()
 var combat = preload("res://tests/gem_v3_combat_tests.gd").new()
 combat.run()
 var result: Dictionary = {"checks": economy.checks+combat.checks, "failures": economy.failures.size()+combat.failures.size(),
  "groups": [{"id":"account_economy_v4","checks":economy.checks,"failures":economy.failures}, {"id":"common_combat","checks":combat.checks,"failures":combat.failures}],
  "scope":"Native v4 gem draw/equip/reforge/salvage account economy and common/fire/ice fixtures. School cores, UI/icons/VFX, and main suite are separate; do not add overlapping runs.",
  "interactive":false,"natural_route":false}
 DirAccess.make_dir_recursive_absolute(OUT)
 FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print("Magic gems v4: %d checks, %d failures" % [result.checks,result.failures])
 quit(1 if result.failures>0 else 0)
