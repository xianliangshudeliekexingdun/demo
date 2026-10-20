"""Independent hand cases and event-order regressions for proposed fire rules."""
from __future__ import annotations

from copy import deepcopy
import heapq
import math
import random

from io_utils import DEFAULT_OUT, ROOT, load, read, write
from model import MODEL_VERSION, Model


def validate(parameters=None):
    inputs = load(parameters) if parameters else load()
    params, base, artifacts, generic = inputs
    tick_damage = base["player"]["attack"]*params["burn"]["tick_coefficient"]
    g04_first_budget = 500 + 8*tick_damage*(1+params["new_profession_items"]["G04"]["detonation_multiplier_add"])
    checks = []

    def check(label, condition, **detail):
        checks.append({"label": label, "pass": bool(condition), **detail})

    def near(label, actual, expected, tolerance=1e-6):
        check(label, abs(actual-expected) <= tolerance, actual=actual, expected=expected)

    def fixture(ids=("F01",), level=1, items=(), scene=None, horizon=10, **profile):
        scenario = deepcopy(scene or params["scenarios"][0])
        return Model(params, base, artifacts, generic, scenario, {"items": list(items), "crit_rate_override": 0, **profile}, ids, level, horizon=horizon)

    def advance(model, until):
        while model.queue and model.queue[0][0] <= until+1e-8:
            model.now, _, _, kind, payload = heapq.heappop(model.queue)
            model.dispatch(kind, payload)
        model.now = until

    def context(ident="F01", cast=1, natural=True, scale=1):
        return {"id": ident, "cast": cast, "natural": natural, "scale": scale, "field": 0}

    # Actual source/default fidelity, kept apart from proposed-rule correctness.
    check("exact retained nine; F04 not silently deleted from runtime", len(params["retained_ids"]) == 9 and "F04" not in params["retained_ids"] and "F04" in base["spells"])
    check("ten proposed fire spells", len(params["retained_ids"])+len(params["new_spells"]) == 10)
    for ident in params["retained_ids"]:
        model = fixture((ident,))
        for key in ("levels", "windup", "cooldown", "range"):
            if key in base["spells"][ident]:
                check("retained raw baseline " + ident + "." + key, model.specs[ident][key] == base["spells"][ident][key])
    geometry = read(ROOT / params["runtime_geometry_source"])
    room = read(ROOT / params["first_room_geometry_source"])
    near("rain impact radius fidelity", params["geometry"]["rain_impact_radius"], geometry["rain"]["impact_radius"])
    near("rain scatter radius fidelity", params["geometry"]["rain_scatter_fraction"], geometry["rain"]["scatter_radius_fraction"])
    near("bolt clearance fidelity", params["geometry"]["bolt_collision_radius"], room["bolt_collision_radius"])
    near("CDR cap 60%", base["limits"]["cooldown_reduction"], .6)
    near("cooldown floor .2 seconds", base["limits"]["minimum_cooldown"], .2)
    check("critical rate no extra cap", base["limits"]["crit_rate"] is None)
    bridge = read(DEFAULT_OUT / "runtime_baseline.json")
    check("real current core independent checks passed", bridge["checks"] > 0 and not bridge["failures"] and bridge["source_stable"])
    for level in (1, 2, 3):
        native = next(r for r in bridge["cases"] if r["spell_id"] == "F06" and r["level"] == level and r["extra_cdr_override"] == .6 and r["horizon"] == 60 and r.get("items") == ["G03"])
        near("actual current G03 starvation verified", native["g03_bursts"], 0)
    for ident, budgets in {"F01": [100, 135, 210], "F07": [500, 650, 800], "F08": [160, 220, 330]}.items():
        for level, expected in enumerate(budgets, 1):
            model = fixture((ident,), level, disable_candidate_burn=True)
            model.cast(ident)
            advance(model, 2)
            near("hand first-cast direct budget " + ident + " L" + str(level), model.metrics["damage"], expected)
    for ident in ("F01", "F07", "F08"):
        for level in range(1, 4):
            for cdr in (0, .6):
                model = fixture((ident,), level, horizon=60, cdr_override=cdr, disable_candidate_burn=True)
                result = model.run()
                native = next(r for r in bridge["cases"] if r["spell_id"] == ident and r["level"] == level and r["extra_cdr_override"] == cdr and r["scene"] == "single_static_anchor" and r["horizon"] == 60)
                count = result["metrics"].get("natural_casts", 0)
                check("continuous schedule differs at most one finite-horizon cast from native", abs(count-native["cast_count"]) <= 1,
                      ident=ident, level=level, cdr=cdr, continuous=count, native=native["cast_count"])

    model = fixture()
    model.ignite(0)
    near("new burn eight future ticks", model.future_ticks(0), 8)
    near("no immediate burn damage", model.metrics["damage"], 0)
    advance(model, .49)
    model.ignite(0)
    near("refresh keeps next tick", model.burns[0].next_tick, .5)
    advance(model, .5)
    near("first refreshed tick exactly .5", model.metrics["damage"], tick_damage)
    near("single shared instance", len(model.burns), 1)
    advance(model, 4.49)
    near("refresh at .49 produces eight ticks, not an immediate ninth", model.metrics["damage"], 8*tick_damage)
    check("burn expires", not model.burns)

    model = fixture()
    model.ignite(0)
    model.schedule(4, 12, "reignite", 0)
    advance(model, 4)
    near("at exact expiry existing last tick precedes re-ignite", model.metrics["damage"], 8*tick_damage)
    near("refresh at expiry future next tick", model.burns[0].next_tick, 4.5)
    near("refreshed expiry has eight future ticks", model.future_ticks(0), 8)
    model = fixture()
    model.ignite(0)
    advance(model, 4)
    near("at expiry last tick not paid twice", model.detonate(0, 1), 0)
    near("expiry no detonation damage", model.metrics["damage"], 8*tick_damage)

    model = fixture()
    model.ignite(0)
    advance(model, 1.2)
    near("future full ticks after two elapsed", model.future_ticks(0), 6)
    model.detonate(0, 1.25)
    near("burn plus 1.25 detonation once", model.metrics["damage"], 2*tick_damage+6*tick_damage*1.25)
    check("detonation consumes burn", not model.burns)
    advance(model, 8)
    near("consumed old queue cannot pay ticks", model.metrics["damage"], 9.5*tick_damage)
    model = fixture(items=("P06",))
    model.ignite(0)
    near("P06 twelve future ticks", model.future_ticks(0), 12)
    advance(model, .5)
    near("P06 does not increase tick damage", model.metrics["damage"], tick_damage)
    model.detonate(0, 1.5)
    near("P06 changes remaining cash-out, not tick rate", model.metrics["damage"], tick_damage+11*tick_damage*1.5)

    model = fixture(("F07", "F11"), items=("G04",))
    model.ignite(0)
    model.post_hit(0, 5, context("F07"), detonate=True)
    near("G04 natural L1 direct500 plus full selected cashout", model.metrics["damage"], g04_first_budget)
    advance(model, .5)
    near("G04 delayed re-ignite has no immediate damage", model.metrics["damage"], g04_first_budget)
    near("G04 applied once", model.metrics["reignites_applied"], 1)
    near("G04 future tick begins .5 later", model.burns[0].next_tick, 1)
    model = fixture(("F07", "F11"), items=("G04",))
    model.ignite(0)
    model.post_hit(0, 5, context("F07", natural=False, scale=.7), detonate=True)
    near("extra F07 direct scales .7, burn cashout is shared x1", model.metrics["damage"], 350+8*tick_damage)
    near("extra F07 cannot G04 re-ignite", model.metrics["reignites_scheduled"], 0)
    dead_scene = deepcopy(params["scenarios"][0])
    dead_scene["health"] = 490
    model = fixture(("F07", "F11"), scene=dead_scene, items=("G04",))
    model.ignite(0)
    model.post_hit(0, 5, context("F07"), detonate=True)
    near("parent kills before detonation", model.metrics["detonations"], 0)
    near("dead parent no G04", model.metrics["reignites_scheduled"], 0)
    dead_scene["health"] = 600
    model = fixture(("F07", "F11"), scene=dead_scene, items=("G04",))
    model.ignite(0)
    model.post_hit(0, 5, context("F07"), detonate=True)
    near("detonation killed target no G04 scheduling", model.metrics["reignites_scheduled"], 0)
    model = fixture(("F07", "F11"), items=("G04",), horizon=10)
    for at in (0, .2, 2):
        model.now = at
        model.ignite(0)
        model.post_hit(0, 1, context("F07", cast=round(at*10)+1), detonate=True)
    near("G04 per-target shared cooldown", model.metrics["reignites_scheduled"], 2)
    model = fixture(("F07", "F11"), items=("G04",))
    model.ignite(0)
    model.post_hit(0, 1, context("F07"), detonate=True)
    model.raw_damage(0, 1e9, "test", "test")
    advance(model, .5)
    near("delayed re-ignite canceled by death", model.metrics["reignites_applied"], 0)
    model = fixture(("F07", "F11"), items=("G04",))
    model.ignite(0)
    model.post_hit(0, 1, context("F07"), detonate=True)
    model.stop_combat()
    advance(model, 4)
    near("combat ended no delayed G04 catch-up", model.metrics["reignites_applied"], 0)
    check("combat end clears burns and regions", not model.burns and not model.zones and not model.queue)

    # F11 remains useful alone and has a measurable spatial niche beyond small splash.
    model = fixture(("F11",))
    model.cast("F11")
    advance(model, 4)
    near("F11 no neighbors direct80 plus full burn", model.metrics["damage"], 80+8*tick_damage)
    scene = deepcopy(params["scenarios"][1])
    scene["health"] = 70
    model = fixture(("F11",), scene=scene)
    model.cast("F11")
    advance(model, 0)
    near("F11 parent kill still spreads from valid impact", model.metrics["propagated_targets"], 2)
    check("F11 dead primary cannot burn", len(model.burns) == 2 and len(model.dead_ids) == 1)
    sparse = next(x for x in params["scenarios"] if x["id"] == "spread_six")
    for level, expected_count in ((1, 2), (2, 3), (3, 4)):
        model = fixture(("F11",), level, scene=sparse)
        model.cast("F11")
        advance(model, 0)
        near("F11 sparse propagation limit L" + str(level), model.metrics["propagated_targets"], expected_count)
        check("F11 no propagation recursion", model.metrics["natural_casts"] == 1 and model.metrics["extra_casts"] == 0)
    model = fixture(("F11",), 3, items=("B11",), scene=sparse)
    model.cast("F11")
    advance(model, 0)
    near("B11 cap+2 bounded by five neighbors", model.metrics["propagated_targets"], 5)
    scene = deepcopy(params["scenarios"][1])
    scene["blocked_spread_pairs"] = [[0, 1], [0, 2], [0, 3]]
    model = fixture(("F11",), 1, scene=scene)
    model.ignite(4)
    model.spread(0, model.spells["F11"])
    near("spread filters already-burning and blocked pairs", model.metrics["propagated_targets"], 1)
    check("spread reaches remaining legal neighbor", 5 in model.burns and 1 not in model.burns)

    # First drop explicitly differs from current random 60%-per-drop runtime.
    for items, first, second in (((), 100, None), (("B03",), 150, 60)):
        model = fixture(("F03",), items=items, disable_candidate_burn=True)
        model.cast("F03")
        advance(model, .3)
        near("candidate first fixed drop coefficient", model.metrics["damage"], first)
        if second is not None:
            advance(model, .7)
            near("B03 second fixed but no second x1.5", model.metrics["damage"], first+second)
        advance(model, 3)
        near("rain total drops stays six", model.metrics["rain_drops"], 6)
    scene = deepcopy(params["scenarios"][0])
    scene["health"] = base["normal_stages"][0]["stats"]["M01"]["health"]
    model = fixture(("F03",), scene=scene)
    model.post_hit(0, 1, context("F03"), ignite=True)
    advance(model, 4)
    check("first100 plus selected burn meets stationary180 anchor", len(model.dead_ids) == 1 and model.metrics["damage"] == 180)
    model = fixture(("F08",), 3)
    model.cast("F08")
    advance(model, 1)
    near("beam secondary does not refresh burn", model.metrics["ignite_applications"], 1)
    for ident in ("F05", "F06"):
        model = fixture((ident,), 3)
        model.cast(ident)
        advance(model, 8)
        near("one ignition per cast/actor first area hit " + ident, model.metrics["ignite_applications"], 1)
    model = fixture(("F07", "F11"), 3)
    model.cast("F07")
    advance(model, .6)
    model.ignite(0)
    advance(model, 1.1)
    near("F07 aftershock cannot detonate new burn", model.metrics["detonations"], 0)
    check("F07 aftershock cannot ignite or consume", bool(model.burns) and model.metrics["ignite_applications"] == 1)

    # F06 cannot recursively increase its own direct zone, while shared burn is current-stat damage.
    model = fixture(("F06",))
    model.cast("F06")
    advance(model, .5)
    near("F06 own direct excludes own 20%", model.by_source["direct"], 40)
    advance(model, 1)
    near("F06 burn reads current field once", model.by_source["burn"], tick_damage*1.2)
    model = fixture(("F03", "F06"), items=("P03",))
    ctx = context("F03")
    model.make_zone("F03", ctx, (0, 2), 0, 4, 0, 2.2, kind="rain")
    model.make_zone("F03", ctx, (0, 2), .4, 3, .5, 2.2, kind="rain_ground")
    near("same F03 rain/ground not two distinct IDs", model.vulnerability(0), 0)
    model.cast("F06")
    near("two distinct area IDs vulnerability20%", model.vulnerability(0), .2)

    # Old-G03 failure at high CDR is a trigger conflict, not loss of spell damage.
    for level in (1, 2, 3):
        new = fixture(("F06",), level, items=("G03",), cdr_override=.6, horizon=60).run()
        old = fixture(("F06",), level, items=("G03",), cdr_override=.6, g03_trigger="expiration", horizon=60).run()
        check("G03 new two-second trigger survives replacement L"+str(level), new["metrics"].get("g03_bursts", 0) > 0)
        near("old G03 expired trigger starves under repeated replacement", old["metrics"].get("g03_bursts", 0), 0)
    model = fixture(("F06",), items=("G03",))
    model.cast("F06", natural=False)
    advance(model, 8)
    near("additional area no G03", model.metrics["g03_bursts"], 0)
    model = fixture(("F06",), items=("G03",))
    model.cast("F06")
    advance(model, 1)
    model.cast("F06")
    advance(model, 2.1)
    near("replaced before two seconds no old burst", model.metrics["g03_bursts"], 0)
    for level, expected in ((1, 0), (2, 0), (3, 1)):
        model = fixture(("F03",), level, items=("G03",))
        model.cast("F03")
        advance(model, 9)
        near("rain marker never triggers; only L3 ground", model.metrics["g03_bursts"], expected)

    model = fixture(("F01", "F02", "F10"), items=("P04", "G01"), horizon=30)
    result = model.run()
    near("P04/G01 extra count bounded, no recursive casts", result["metrics"].get("extra_casts", 0), 2*(result["metrics"]["natural_casts"]//3))
    near("shared burning does not count as natural casts", model.natural_count, result["metrics"]["natural_casts"])
    model = fixture(("F01",), 3, items=("P02",), crit_rate_override=1)
    model.cast("F01")
    advance(model, 8)
    near("P02 once per natural cast despite two direct hits", len(model.patch_casts), 1)
    near("P02 derived ticks do not re-ignite", model.metrics["ignite_applications"], 2)
    near("P02 derived ticks do not add natural casts", model.natural_count, 1)

    model = fixture(items=("GT01", "GU11"), crit_rate_override=1)
    model.shield_restore(100)
    near("full shield no stored recovery", model.charge, 0)
    model.shield -= 40
    model.shield_restore(5)
    near("actual shield restore to charge", model.charge, 25)
    model.post_hit(0, 1, context())
    near("fixed charge cannot crit or receive fire multipliers", model.by_source["fixed_charge"], 25)
    near("direct independently critical", model.by_source["direct"], 150)
    model = fixture(items=("GT01", "GU11"))
    model.post_hit(0, 1, context())
    model.shield -= 40
    model.shield_restore(5)
    model.post_hit(0, 1, context())
    near("empty first-hit check consumed for cast", model.metrics["charge_releases"], 0)
    model.ignite(0)
    advance(model, .5)
    near("burn cannot release GT01", model.metrics["charge_releases"], 0)
    near("stored charge remains", model.charge, 25)
    dead_scene["health"] = 100
    model = fixture(("F07", "F11"), items=("GT01", "GU11", "G04"), scene=dead_scene)
    model.shield = 0
    model.shield_restore(5)
    model.ignite(0)
    model.post_hit(0, .8, context("F07"), detonate=True)
    near("GT01 kills after direct, suppresses detonation", model.metrics["detonations"], 0)
    near("GT01 kill no G04", model.metrics["reignites_scheduled"], 0)

    for crit in (1, 1.8):
        model = fixture(crit_rate_override=crit)
        model.post_hit(0, 1, context())
        near("crit>=100% no super-critical", model.metrics["damage"], 150)
    model = fixture(("F01", "F02", "F03"), 3, cdr_override=.9)
    near("CDR aggregate caps at60", model.total_cdr(), .6)
    model.spells["F01"]["cooldown"] = .1
    near("CDR .2 floor", model.cooldown("F01"), .2)
    model.post_hit(0, 1, context())
    near("fire mastery/synergy additive bucket", model.by_source["direct"], 150)
    model = fixture(("F01", "F02", "F03"), 3, crit_rate_override=1)
    model.post_hit(0, 1, context())
    near("F02 level3 adds .25 crit multiplier", model.by_source["direct"], 100*1.5*1.75)

    # Regression: wait for valid target/deficit, then apply full windup and recheck.
    model = fixture(("F10",), horizon=5, shield_loss_feed={"interval": 3, "amount": 30})
    result = model.run()
    near("shield deficit starts a fresh .35-second windup", result["casts_at"]["F10"][0], 3.35)
    model = fixture(("F10",))
    model.shield = 0
    model.cooldown_ready = {"F10": 0}
    model.version["F10"] = 1
    model.dispatch("cast_begin", ("F10", 1))
    advance(model, .2)
    model.shield = model.shield_max
    advance(model, .35)
    near("filled during windup cancels shield natural release", model.metrics["natural_casts"], 0)
    model.health[0] = 0
    model.shield = 0
    check("shield cannot cast after last enemy dead", not model.cast("F10"))
    scene = deepcopy(params["scenarios"][0])
    scene["motion"] = "sinusoidal"
    scene["amplitude_x"], scene["amplitude_y"], scene["period"], scene["phase_per_actor"] = 2, 1, 5, 0
    model = fixture(("F07",), scene=scene)
    model.now = 2
    model.cast("F07", natural=False)
    payload = next(event[4] for event in model.queue if event[3] == "impact")
    check("extra F07 locks current impact aim without phantom windup", payload[3] == model.position(0, 2))
    model = fixture(("F01",), 3)
    model.cast("F01")
    check("secondary bolt targets at .18 spawn, not .33 landing", any(event[0] == .18 and event[3] == "secondary_bolt" for event in model.queue))

    rng = random.Random(20261018)
    for items in ((), ("P06",)):
        for trial in range(100):
            model = fixture(items=items, horizon=30)
            model.ignite(0)
            times = sorted(rng.random()*8 for _ in range(20))
            for at in times:
                advance(model, at)
                model.ignite(0)
                check("refresh fuzz retains bounded complete tick budget", 0 <= model.future_ticks(0) <= model.burn_rule["maximum_future_ticks"] and not model.failed_guards)
            advance(model, 20)
            check("refresh fuzz terminates", not model.burns and not model.failed_guards)
    result = {"model_version": MODEL_VERSION, "parameter_version": params["model_version"], "checks": len(checks), "failures": [x for x in checks if not x["pass"]], "details": checks,
              "scope": "Current-source contracts, actual-core baseline hand cases, hypothetical rule boundary and seeded state fuzz; not full-route or combat playtest"}
    return result


if __name__ == "__main__":
    result = validate()
    write(DEFAULT_OUT / "model_validation.json", result)
    print(f"FORMAL_FIRE_VALIDATION checks={result['checks']} failures={len(result['failures'])}")
    for failure in result["failures"]:
        print(failure)
    raise SystemExit(1 if result["failures"] else 0)
