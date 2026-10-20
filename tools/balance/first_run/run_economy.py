"""Reproducible gold/stock/rarity tuning, independent of the game runtime."""
from __future__ import annotations

import argparse
from collections import Counter
from copy import deepcopy
import csv
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import zlib

from artifacts import ArtifactCombat, eligible, resolve_catalog
from economy import Economy, ECONOMY_MODEL_VERSION, RARITIES, make_offer, room_income, tier_probabilities
from model import build_at
from run import load, quantile

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "data/balance_candidates/run_economy_v1.json"
SCENARIOS = Path(__file__).with_name("economy_scenarios.json")


def distribution(values):
    return {"median": statistics.median(values), "p10": quantile(values, 0.1),
            "p90": quantile(values, 0.9), "mean": statistics.mean(values),
            "mean_standard_error": statistics.stdev(values) / math.sqrt(len(values)) if len(values) > 1 else 0}


def validate(config, base, catalog, spells, assumptions):
    checks = []

    def check(name, passed):
        if not passed:
            raise AssertionError(name)
        checks.append({"case": name, "status": "pass"})

    check("stage ranges cover each of 60 rooms once", [r for s in config["stages"] for r in range(s["from"], s["to"] + 1)] == list(range(1, 61)))
    check("positive integer prices", all(type(x) is int and x > 0 for x in config["prices"].values()))
    check("nonnegative integer sources", all(type(x) is int and x >= 0 for s in config["stages"] for x in (s["clear_gold"], s["elite_bonus"])))
    check("initial bank is nonnegative integer", type(config["currency"]["initial"]) is int and config["currency"]["initial"] >= 0)
    check("unsupported income loops remain disabled", all(config["income"][k] == 0 for k in ("kill_gold", "performance_bonus", "sale_refund", "exhausted_pool_gold")))
    check("no final in-run reward", not config["income"]["final_room_in_run_reward"])
    check("purchase limit is positive integer or absent", config["shop"].get("max_purchases_per_visit") is None or (type(config["shop"]["max_purchases_per_visit"]) is int and config["shop"]["max_purchases_per_visit"] > 0))
    check("all stage weights finite, nonnegative and total 100", all(set(s["rarity_weights"]) == set(RARITIES) and sum(s["rarity_weights"].values()) == 100 and all(math.isfinite(x) and x >= 0 for x in s["rarity_weights"].values()) for s in config["stages"]))
    check("21 unique items: 12 blue, 6 purple, 3 gold", Counter(i["rarity"] for i in catalog["items"].values()) == {"blue": 12, "purple": 6, "gold": 3})
    check("seven elite plus two boss chests", len(base["elites"]) + len(base["recovery"]["boss_after"]) == 9)
    fixture = deepcopy(config)
    for s in fixture["stages"]:
        s["clear_gold"], s["elite_bonus"] = 3, 7
    fixture["income"]["boss_bonus"] = {"15": 13, "45": 17}
    check("hand: nine rooms x3 + one elite x7 = 34", sum(room_income(fixture, base, r) for r in range(1, 10)) == 34)
    check("hand: 15 rooms x3 + two elites x7 + boss13 = 72", sum(room_income(fixture, base, r) for r in range(1, 16)) == 72)
    check("hand: 59x3 + seven elites x7 + bosses30 = 256", sum(room_income(fixture, base, r) for r in range(1, 61)) == 256)
    synthetic = {"a": {"rarity": "blue"}, "b": {"rarity": "blue"}, "p": {"rarity": "purple"}, "g": {"rarity": "gold"}}
    weights = {"blue": 10, "purple": 30, "gold": 60}
    check("missing gold tier renormalizes to 1/4 and 3/4", tier_probabilities(synthetic, ["a", "p"], weights) == {"blue": .25, "purple": .75})
    check("empty pool terminates", make_offer(synthetic, ["a"], {"a"}, weights, 3, random.Random(1))[0] == [])
    offer, logs = make_offer(synthetic, ["a", "p"], set(), weights, 3, random.Random(1))
    check("small pool shows two unique candidates", set(offer) == {"a", "p"} and len(offer) == 2)
    offer, logs = make_offer(synthetic, list(synthetic), {"g"}, weights, 3, random.Random(3), "gold")
    check("exhausted guaranteed tier falls back to highest remaining legal tier", offer[0] == "p" and "g" not in offer)
    offer, logs = make_offer(synthetic, ["a", "p", "g"], set(), {"blue": 75, "purple": 25, "gold": 0}, 3, random.Random(2), "gold")
    check("zero-weight gold cannot be introduced by fallback", "g" not in offer and offer[0] == "p")
    check("all-zero eligible weights terminate", make_offer(synthetic, ["g"], set(), {"blue": 1, "purple": 1, "gold": 0}, 3, random.Random(1))[0] == [])
    hits = sum(make_offer(synthetic, ["a", "p"], set(), weights, 1, random.Random(i))[0] == ["p"] for i in range(20000))
    check("single-slot MC matches analytic 75pct within four standard errors", abs(hits / 20000 - .75) < 4 * math.sqrt(.75 * .25 / 20000))
    full_pool = {f"{t}{n}": {"rarity": t} for t in RARITIES for n in range(3)}
    gold_hits = sum(any(full_pool[i]["rarity"] == "gold" for i in make_offer(full_pool, list(full_pool), set(), {"blue":50,"purple":40,"gold":10}, 3, random.Random(i))[0]) for i in range(10000))
    expectation = 1 - .9 ** 3
    check("three ordinary slots: at least one gold matches analytic 27.1pct", abs(gold_hits / 10000 - expectation) < 4 * math.sqrt(expectation * (1 - expectation) / 10000))
    no_offense = {"F04":3,"F02":3,"F10":3}
    legal = [i for i, item in catalog["items"].items() if eligible(base, no_offense, item)]
    offer, _ = make_offer(catalog["items"], legal, set(), config["stages"][1]["rarity_weights"], 3, random.Random(1), "gold")
    check("actual all-support build never receives unusable guaranteed gold", not any(i.startswith("G") for i in offer) and catalog["items"][offer[0]]["rarity"] == "purple")
    engine = Economy(config, base, catalog, spells, assumptions)
    check("current-room new spell can qualify its artifact", "B02" in engine.legal["burst", 6])
    for path in spells["paths"]:
        for room in engine.shops | engine.chests:
            pool = engine.legal[path, room]
            check(f"quality probabilities sum to one or empty: {path}/{room}", (not pool) or abs(sum(tier_probabilities(engine.items, pool, config["stages"][0]["rarity_weights"]).values()) - 1) < 1e-9)
        for policy in assumptions["policies"]:
            for seed in (17, 1003):
                result = engine.campaign(path, policy, seed, trace=True)
                check(f"conservation and uniqueness {path}/{policy}/{seed}", result["bank"] == config["currency"]["initial"] + result["earned"] - result["spent"] and result["bank"] >= 0 and len(result["owned"]) == len(set(result["chosen"] + result["purchased"])))
                check(f"one reward per node and never after final {path}/{policy}/{seed}", len(result["trace"]) == 14 and len({(e["room"], e["source"]) for e in result["trace"]}) == 14 and all(e["room"] < 60 for e in result["trace"]))
    bought, rest = engine.purchase("burst", "balanced", ["U01", "U01", "U02"], config["prices"]["blue"], {"U01"})
    check("reopened inventory cannot resell bought or duplicate items", bought == ["U02"] and rest == 0)
    bought, rest = engine.purchase("burst", "balanced", ["U01"], config["prices"]["blue"] - 1, set())
    check("cannot buy below exact price", not bought and rest == config["prices"]["blue"] - 1)
    bought, rest = engine.purchase("burst", "save_gold", ["G01", "U01"], config["prices"]["gold"] + config["prices"]["blue"], set())
    limit = config["shop"].get("max_purchases_per_visit")
    check("saving obeys visit purchase limit", set(bought) == ({"G01"} if limit == 1 else {"G01", "U01"}) and rest == (config["prices"]["blue"] if limit == 1 else 0))
    if limit:
        bought, rest = engine.purchase("burst", "balanced", ["U02"], config["prices"]["blue"], {"U01"}, purchased_count=limit)
        check("reopening cannot reset visit purchase limit", not bought and rest == config["prices"]["blue"])
    bought, _ = engine.purchase("burst", "save_gold", ["U01"], config["prices"]["blue"], set(), room=min(engine.shops))
    check("saving policy still buys early blue to establish first-room power", bought == ["U01"])
    return checks


def batch(engine, path, policy, count, scenario):
    seed_base = scenario["seed"] + zlib.crc32(path.encode("utf-8"))
    results = [engine.campaign(path, policy, seed_base + i) for i in range(count)]
    items = engine.items
    totals = Counter()
    for r in results:
        totals.update({(v["source"], v["stage"], v["tier"]): v["count"] for v in r["offer_tiers"]})
    effective = []
    for source in ("chest", "shop"):
        for stage in engine.config["stages"]:
            n = sum(totals[source, stage["id"], tier] for tier in RARITIES)
            effective.append({"source": source, "stage": stage["id"], "slots": n,
                              "probabilities": {tier: totals[source, stage["id"], tier] / n if n else 0 for tier in RARITIES}})
    visits = []
    for idx, room in enumerate(sorted(engine.shops)):
        rows = [r["visits"][idx] for r in results]
        visits.append({"room": room, "arrival": distribution([v["arrival"] for v in rows]),
                       "purchases": distribution([v["purchases"] for v in rows]),
                       "affordable_rate": statistics.mean(v["affordable"] for v in rows),
                       "no_purchase_rate": statistics.mean(v["purchases"] == 0 for v in rows),
                       "gold_offered_rate": statistics.mean(v["gold_offered"] for v in rows),
                       "gold_budget_rate": statistics.mean(v["gold_affordable"] for v in rows)})
    first = [r["first_gold_room"] for r in results if r["first_gold_room"] is not None]
    row = {"path": path, "policy": policy, "trials": count,
           "purchases": distribution([len(r["purchased"]) for r in results]),
           "owned": distribution([len(r["owned"]) for r in results]),
           "gold_owned": distribution([sum(items[i]["rarity"] == "gold" for i in r["owned"]) for r in results]),
           "spent": distribution([r["spent"] for r in results]), "leftover": distribution([r["bank"] for r in results]),
           "zero_gold_rate": statistics.mean(r["first_gold_room"] is None for r in results),
           "never_offered_gold_rate": statistics.mean(r["first_gold_offered_room"] is None for r in results),
           "preferred_first_item_obtained_rate": statistics.mean(scenario["preferred_items"][path][0] in r["owned"] for r in results),
           "generic_owned_rates": {i: statistics.mean(i in r["owned"] for r in results) for i in ("U01","U02","U03")},
           "no_gold_before_45_rate": statistics.mean(r["checkpoints"][45]["gold"] == 0 for r in results),
           "first_gold_room_when_obtained": distribution(first) if first else None,
           "empty_chest_campaign_rate": statistics.mean(r["empty_chests"] > 0 for r in results),
           "thin_offer_campaign_rate": statistics.mean(r["thin_offers"] > 0 for r in results),
           "visits": visits, "effective_slot_probabilities": effective,
           "checkpoints": {str(room): {k: distribution([r["checkpoints"][room][k] for r in results]) for k in ("bank", "owned", "gold")} for room in (15,45,60)},
           "independent_seed_halves": [statistics.mean(r["first_gold_room"] is None for r in half) for half in (results[:count//2], results[count//2:])]}
    return row, results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--scenarios", type=Path, default=SCENARIOS)
    parser.add_argument("--out", type=Path, default=ROOT / "build/qa/run-economy-20261017/selected")
    parser.add_argument("--trials", type=int)
    parser.add_argument("--without-guarantees", action="store_true")
    parser.add_argument("--no-sweep", action="store_true")
    parser.add_argument("--no-combat", action="store_true")
    parser.add_argument("--set", action="append", default=[], metavar="PATH=JSON")
    args = parser.parse_args()
    raw_config = load(args.config)
    config, scenario = deepcopy(raw_config), load(args.scenarios)
    for override in args.set:
        key, value = override.split("=", 1)
        target = config
        parts = key.split(".")
        for part in parts[:-1]:
            target = target[int(part)] if isinstance(target, list) else target[part]
        target[int(parts[-1]) if isinstance(target, list) else parts[-1]] = json.loads(value)
    if args.without_guarantees:
        config["guarantees"]["shop"] = {}
        config["guarantees"]["chest"] = {}
    if args.trials:
        if args.trials < 2:
            raise ValueError("At least two trials")
        scenario["trials"] = args.trials
    base_path = args.config.parent / config["base_parameters"]
    catalog_path = args.config.parent / config["artifact_catalog"]
    spell_path = Path(__file__).with_name("scenarios.json")
    artifact_assumptions_path = Path(__file__).with_name("artifact_scenarios.json")
    base, raw_catalog, spells = load(base_path), load(catalog_path), load(spell_path)
    catalog = resolve_catalog(base, raw_catalog)
    artifact_assumptions = load(artifact_assumptions_path)
    checks = validate(config, base, catalog, spells, scenario)
    engine = Economy(config, base, catalog, spells, scenario)
    rows, samples, combat = [], [], []
    for path in scenario["ordinary_paths"] + scenario["boundary_paths"]:
        policies = scenario["policies"] if path in scenario["ordinary_paths"] else ["balanced"]
        for policy in policies:
            row, results = batch(engine, path, policy, scenario["trials"], scenario)
            rows.append(row)
            samples.append({"path": path, "policy": policy, "campaign": engine.campaign(path, policy, scenario["seed"] + zlib.crc32(path.encode()), trace=True)})
            if not args.no_combat and policy in ("balanced", "no_shop"):
                n = min(scenario["combat_probes_per_route"], len(results))
                build = build_at(spells["paths"][path], 60)
                kind = spells["paths"][path]["profile"]
                boss = base["bosses"][-1]
                probes = []
                for j in range(n):
                    idx = j * len(results) // n
                    r = ArtifactCombat(base, catalog, results[idx]["owned"], build, spells["profiles"][kind],
                                       artifact_assumptions["assumptions"][kind], [dict(boss, boss=boss)],
                                       scenario["seed"] + idx, artifact_assumptions["ttk_horizon"]).run()
                    probes.append({"trial_index": idx, "owned": results[idx]["owned"], "time": r["time"], "status": r["status"]})
                combat.append({"path": path, "policy": policy, "n": n, "ttk": distribution([p["time"] for p in probes]), "timeouts": sum(p["status"] != "clear" for p in probes), "probes": probes})
            print(f"{path}/{policy}: shop {row['purchases']['median']}, items {row['owned']['median']}, zero-gold {row['zero_gold_rate']:.3f}", flush=True)
    sweeps = []
    if not args.no_sweep:
        for variant in scenario["sweeps"]:
            candidate = deepcopy(config)
            if "income_multiplier" in variant:
                for stage in candidate["stages"]:
                    for key in ("clear_gold", "elite_bonus"):
                        stage[key] = round(stage[key] * variant["income_multiplier"])
                candidate["income"]["boss_bonus"] = {k: round(v * variant["income_multiplier"]) for k, v in candidate["income"]["boss_bonus"].items()}
            if "price_multiplier" in variant:
                candidate["prices"] = {k: round(v * variant["price_multiplier"]) for k, v in candidate["prices"].items()}
            if "middle_weights" in variant:
                candidate["stages"][1]["rarity_weights"] = variant["middle_weights"]
            sweep_engine = Economy(candidate, base, catalog, spells, scenario)
            for path in scenario["ordinary_paths"]:
                row, _ = batch(sweep_engine, path, "balanced", scenario["sweep_trials"], scenario)
                sweeps.append({"variant": variant["name"], "parameters": candidate, "row": row})
            print(f"sweep {variant['name']} complete", flush=True)
    targets = []
    for row in rows:
        if row["policy"] != "balanced" or row["path"] not in scenario["ordinary_paths"]:
            continue
        for metric, key in (("ordinary_shop_purchases_median", "purchases"), ("ordinary_final_owned_median", "owned"), ("ordinary_gold_owned_median", "gold_owned")):
            lo, hi = scenario["targets"][metric]
            value = row[key]["median"]
            targets.append({"path": row["path"], "target": metric, "value": value, "status": "within" if lo <= value <= hi else "outside"})
        targets.append({"path": row["path"], "target": "first_shop_affordable_rate", "value": row["visits"][0]["affordable_rate"], "status": "within" if row["visits"][0]["affordable_rate"] >= scenario["targets"]["first_shop_affordable_rate"] else "outside"})
        targets.append({"path": row["path"], "target": "reward_pool_exhaustion_rate_max", "value": row["empty_chest_campaign_rate"], "status": "within" if row["empty_chest_campaign_rate"] <= scenario["targets"]["reward_pool_exhaustion_rate_max"] else "outside"})
    paths = {"economy": args.config, "base": base_path, "catalog": catalog_path, "spell_scenarios": spell_path,
             "economy_scenarios": args.scenarios, "artifact_scenarios": artifact_assumptions_path,
             "economy_model": Path(__file__).with_name("economy.py"), "runner": Path(__file__),
             "combat_model": Path(__file__).with_name("model.py"), "artifact_model": Path(__file__).with_name("artifacts.py")}
    result = {"model_version": ECONOMY_MODEL_VERSION, "input_hashes": {k: {"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for k, p in paths.items()},
              "parameters": config, "source_parameters": raw_config, "assumptions": scenario, "checks": checks,
              "income_ledger": [{"shop_after": r, "increment_since_previous_shop": sum(engine.income[k] for k in range((0 if i == 0 else sorted(engine.shops)[i-1]) + 1, r+1)), "cumulative_earned": sum(engine.income[k] for k in range(1,r+1))} for i, r in enumerate(sorted(engine.shops))],
              "total_run_income": sum(engine.income.values()), "rows": rows, "targets": targets, "sweeps": sweeps, "combat_probes": combat,
              "limits": ["Conditional on reaching each room; not a success-rate or loss forecast", "Fixed spell-choice paths, deterministic hypothetical preferences; not optimal or observed purchasing", "No spatial combat or real AI; TTK probes restart final encounter and do not simulate run attrition", "Effective slot probabilities include forced slots and finite-pool depletion; not nominal independent box odds"]}
    args.out.mkdir(parents=True, exist_ok=True)
    for filename, content in (("results.json", result), ("parameters_used.json", config), ("scenarios_used.json", scenario), ("sample_campaigns.json", samples)):
        (args.out / filename).write_text(json.dumps(content, ensure_ascii=False, indent=2), encoding="utf-8")
    with (args.out / "summary.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["path", "policy", "trials", "purchases_median", "owned_p10", "owned_median", "owned_p90", "gold_median", "zero_gold_rate", "empty_chest_rate", "leftover_median"])
        writer.writerows([r["path"], r["policy"], r["trials"], r["purchases"]["median"], r["owned"]["p10"], r["owned"]["median"], r["owned"]["p90"], r["gold_owned"]["median"], r["zero_gold_rate"], r["empty_chest_campaign_rate"], r["leftover"]["median"]] for r in rows)
    print(f"checks={len(checks)}, groups={len(rows)}, targets_outside={sum(t['status'] != 'within' for t in targets)}, saved={args.out}", flush=True)


if __name__ == "__main__":
    main()
