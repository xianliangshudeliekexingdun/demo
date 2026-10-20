"""Exact rarity renewal/type-collection model and deterministic dust ledgers.

Random gold effects stay fully random; no wishlist, choice or duplicate protection.
Economy forecasts are projections, not the currently reward-isolated45-room route.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import random
import statistics

ROOT = Path(__file__).resolve().parents[3]
MODEL_VERSION = "gem-draw-renewal-1.1"
QUALITIES = ("green", "blue", "purple", "gold")
EPS = 1e-10


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def gold_probability(misses, novice, cfg):
    pity = cfg["pity"]
    turn = misses + 1
    hard = pity["first_gold"] if novice else pity["gold_hard"]
    if turn >= hard:
        return 1.0
    probability = cfg["base_weights"]["gold"] / sum(cfg["base_weights"].values())
    if turn >= pity["gold_soft_start"]:
        probability += (turn - pity["gold_soft_start"] + 1) * pity["gold_soft_increment"]
    return min(1.0, probability)


def quality_probabilities(state, cfg):
    gold_misses, purple_misses, novice = state
    gold = gold_probability(gold_misses, novice, cfg)
    if purple_misses + 1 >= cfg["pity"]["purple_or_better"]:
        return {"green": 0.0, "blue": 0.0, "purple": 1 - gold, "gold": gold}
    weights = cfg["base_weights"]
    denominator = sum(weights[q] for q in QUALITIES if q != "gold")
    result = {q: (1 - gold) * weights[q] / denominator for q in QUALITIES if q != "gold"}
    result["gold"] = gold
    return result


def transition(state, quality):
    gold_misses, purple_misses, novice = state
    if quality == "gold":
        return 0, 0, False
    return gold_misses + 1, (0 if quality == "purple" else purple_misses + 1), novice


def quantile_pmf(pmf, fraction):
    cumulative = 0.0
    for draw, mass in sorted(pmf.items()):
        cumulative += mass
        if cumulative >= fraction - 1e-12:
            return draw
    return None


def cycle_exact(cfg, novice=False):
    """Regeneration at a gold draw resets both quality counters exactly."""
    states = {(0, 0, novice): 1.0}
    pmf, rewards = defaultdict(float), Counter()
    hard = cfg["pity"]["first_gold"] if novice else cfg["pity"]["gold_hard"]
    for draw in range(1, hard + 1):
        following = defaultdict(float)
        for state, mass in states.items():
            for quality, probability in quality_probabilities(state, cfg).items():
                weight = mass * probability
                rewards[quality] += weight
                if quality == "gold":
                    pmf[draw] += weight
                elif weight:
                    following[transition(state, quality)] += weight
        states = following
    mean = sum(draw * mass for draw, mass in pmf.items())
    variance = sum((draw - mean) ** 2 * mass for draw, mass in pmf.items())
    return {"mean": mean, "variance": variance, "p10": quantile_pmf(pmf, .1), "p50": quantile_pmf(pmf, .5),
            "p90": quantile_pmf(pmf, .9), "p95": quantile_pmf(pmf, .95), "p99": quantile_pmf(pmf, .99),
            "maximum": hard, "pmf": dict(pmf), "remaining_mass": sum(states.values()),
            "expected_counts": dict(rewards), "effective_rates": {q: rewards[q] / mean for q in QUALITIES}}


def core_wait_exact(cfg, goal, novice=True):
    """Absorbing DP: count of distinct core types, or one named type, or any gold."""
    n = len(cfg["gold_effects"]["weights"])
    states = {(0, novice, 0): 1.0}
    pmf, survival, mean = {}, 1.0, 0.0
    for draw in range(1, cfg["exact"]["max_draws"] + 1):
        mean += survival
        following = defaultdict(float)
        success = 0.0
        for (misses, first, known), mass in states.items():
            gold = gold_probability(misses, first, cfg)
            following[misses + 1, first, known] += mass * (1 - gold)
            chance = 1.0 if goal == "any" else (1 / n if goal == "specified" else (n - known) / n)
            next_known = known + 1
            if goal in ("any", "specified") or next_known == n:
                success += mass * gold * chance
            else:
                following[0, False, next_known] += mass * gold * chance
            if chance < 1:
                following[0, False, known] += mass * gold * (1 - chance)
        pmf[draw] = success
        # Remove true zero entries at hard pity to keep impossible counters out.
        states = {k: v for k, v in following.items() if v > 0}
        survival = sum(states.values())
        if survival < cfg["exact"]["tail_tolerance"]:
            break
    cdf, cumulative = {}, 0.0
    for draw, probability in pmf.items():
        cumulative += probability
        cdf[draw] = cumulative
    return {"goal": goal, "novice": novice, "mean": mean, "p10": quantile_pmf(pmf, .1),
            "p50": quantile_pmf(pmf, .5), "p90": quantile_pmf(pmf, .9),
            "p95": quantile_pmf(pmf, .95), "p99": quantile_pmf(pmf, .99),
            "guaranteed_maximum": (cfg["pity"]["first_gold"] if novice else cfg["pity"]["gold_hard"]) if goal == "any" else None,
            "residual_probability": survival, "computed_to": draw, "pmf": pmf, "cdf": cdf}


def quality_exposure(cfg, exposures):
    states = {(0, 0, True): 1.0}
    accumulated, snapshots = Counter(), {}
    for draw in range(1, max(exposures) + 1):
        following = defaultdict(float)
        for state, mass in states.items():
            for quality, probability in quality_probabilities(state, cfg).items():
                weight = mass * probability
                accumulated[quality] += weight
                if weight:
                    following[transition(state, quality)] += weight
        states = following
        if draw in exposures:
            snapshots[draw] = {"draws": draw, "expected_counts": dict(accumulated), "state_mass": sum(states.values())}
    return snapshots


def cdf_at(distribution, draws):
    if draws <= 0:
        return 0.0
    cdf = distribution["cdf"]
    return cdf.get(draws, cdf[max(cdf)])


def projected_income(cleared, sources, formal_bosses=False):
    amount = 0
    for room in range(1, cleared + 1):
        stage = next(s for s in sources["economy"]["stages"] if s["from"] <= room <= s["to"])
        amount += sources["meta"]["currency"]["room_dust_by_stage"][stage["id"]]
        if formal_bosses:
            for boss in sources["base"]["bosses"]:
                if boss["room"] == room:
                    amount += sources["meta"]["currency"]["boss_bonus_by_id"][boss["id"]]
    return amount


def ledger(cfg, income, purchases, waits):
    balance, total, spent_draws, spent_catalysts = cfg["income_projection"]["starting_dust"], 0, 0, 0
    queue = list(purchases)
    draws = 0
    rows = []
    for session in range(1, cfg["income_projection"]["forecast_sessions"] + 1):
        balance += income
        total += income
        while queue and balance >= queue[0]:
            cost = queue.pop(0)
            balance -= cost
            spent_catalysts += cost
        current_draws = 0
        if not queue:
            current_draws = balance // cfg["draw_cost"]
            balance -= current_draws * cfg["draw_cost"]
            spent_draws += current_draws * cfg["draw_cost"]
            draws += current_draws
        rows.append({"session": session, "earned": total, "catalyst_spend": spent_catalysts,
                     "draw_spend": spent_draws, "balance": balance, "draws_this_session": current_draws,
                     "total_draws": draws, "first_gold_probability": cdf_at(waits["any"], draws),
                     "specified_core_probability": cdf_at(waits["specified"], draws),
                     "all_cores_probability": cdf_at(waits["all"], draws), "pending_catalyst_costs": queue[:]})
    mean_first_run, previous = 0.0, 0.0
    for row in rows:
        current = row["first_gold_probability"]
        mean_first_run += row["session"] * (current - previous)
        previous = current
    return {"income_per_session": income, "purchases": purchases, "rows": rows,
            "mean_session_to_first_gold": mean_first_run if previous > 1 - EPS else None,
            "guaranteed_session_to_first_gold": next((r["session"] for r in rows if r["total_draws"] >= cfg["pity"]["first_gold"]), None)}


def sample_draw(state, cfg, rng):
    threshold = rng.random()
    cumulative = 0.0
    probabilities = quality_probabilities(state, cfg)
    for quality in QUALITIES:
        cumulative += probabilities[quality]
        if probabilities[quality] > 0 and threshold < cumulative:
            return quality, transition(state, quality)
    if abs(cumulative - 1) < 1e-12:
        quality = next(q for q in reversed(QUALITIES) if probabilities[q] > 0)
        return quality, transition(state, quality)
    raise AssertionError("Probability table did not sum to one")


def sample_batch(cfg, seed):
    rng = random.Random(seed)
    accounts = cfg["monte_carlo"]["accounts_per_seed"]
    draws = cfg["monte_carlo"]["draws_per_account"]
    n = len(cfg["gold_effects"]["weights"])
    quality_counts, first_gold_times = Counter(), []
    desired_by_horizon, all_by_horizon = [], []
    per_account_gold = []
    per_account_quality_rates = defaultdict(list)
    violations = 0
    rare_ready = []
    for _ in range(accounts):
        state = (0, 0, True)
        seen = set()
        rare_count = 0
        first_gold, target_at = None, None
        account_golds = 0
        account_quality = Counter()
        for draw in range(1, draws + 1):
            old_state = state
            quality, state = sample_draw(state, cfg, rng)
            quality_counts[quality] += 1
            account_quality[quality] += 1
            if quality in ("purple", "gold"):
                rare_count += 1
            if quality == "gold":
                account_golds += 1
                ident = rng.randrange(n)
                seen.add(ident)
                if ident == 0 and target_at is None:
                    target_at = draw
                if first_gold is None:
                    first_gold = draw
            if state[1] >= cfg["pity"]["purple_or_better"] or state[0] >= (cfg["pity"]["first_gold"] if state[2] else cfg["pity"]["gold_hard"]):
                violations += 1
            if old_state[0] + 1 >= (cfg["pity"]["first_gold"] if old_state[2] else cfg["pity"]["gold_hard"]) and quality != "gold":
                violations += 1
        first_gold_times.append(first_gold)
        desired_by_horizon.append(target_at is not None)
        all_by_horizon.append(len(seen) == n)
        per_account_gold.append(account_golds)
        rare_ready.append(rare_count >= 4)
        for quality in QUALITIES:
            per_account_quality_rates[quality].append(account_quality[quality] / draws)
    return {"seed": seed, "accounts": accounts, "draws_per_account": draws,
            "observed_quality_rates": {q: quality_counts[q] / (accounts * draws) for q in QUALITIES},
            "quality_rate_standard_errors": {q: statistics.stdev(per_account_quality_rates[q]) / math.sqrt(accounts) for q in QUALITIES},
            "mean_first_gold": statistics.mean(first_gold_times), "max_first_gold": max(first_gold_times),
            "mean_gold_per_account": statistics.mean(per_account_gold),
            "gold_count_stdev": statistics.stdev(per_account_gold),
            "specified_core_probability": statistics.mean(desired_by_horizon),
            "all_core_probability": statistics.mean(all_by_horizon),
            "four_three_affix_gems_probability": statistics.mean(rare_ready),
            "guarantee_violations": violations}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parameters", type=Path, default=Path(__file__).with_name("draw_parameters.json"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/qa/magic-gem-draws-20261019")
    args = parser.parse_args()
    args.output = args.output.resolve()
    if not args.output.is_relative_to((ROOT / "build/qa").resolve()):
        raise ValueError("Reports must stay under build/qa")
    cfg = load(args.parameters)
    source_paths = {k: ROOT / p for k, p in cfg["sources"].items()}
    sources = {k: load(p) for k, p in source_paths.items()}
    hashes = {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p) for p in source_paths.values()}
    validation = []

    def check(name, actual, expected=True):
        ok = math.isclose(actual, expected, abs_tol=2e-7, rel_tol=1e-9) if isinstance(actual, (int, float)) and isinstance(expected, (int, float)) else actual == expected
        validation.append({"name": name, "actual": actual, "expected": expected, "pass": ok})

    check("base table sums to100", sum(cfg["base_weights"].values()), 100)
    check("positive integral draw cost", isinstance(cfg["draw_cost"], int) and cfg["draw_cost"] > 0)
    check("quality weights nonnegative", all(v >= 0 for v in cfg["base_weights"].values()))
    check("pity thresholds coherent", 1 <= cfg["pity"]["first_gold"] <= cfg["pity"]["gold_hard"] and 1 <= cfg["pity"]["purple_or_better"] <= cfg["pity"]["gold_hard"])
    check("uniform effects not protected", len(set(cfg["gold_effects"]["weights"].values())), 1)
    check("all8 current designed core effects", sorted(cfg["gold_effects"]["weights"]), sorted(sources["gem_design"]["cores"]))
    check("positive core effect weights", all(v > 0 for v in cfg["gold_effects"]["weights"].values()))
    check("no wishlist", cfg["gold_effects"]["wishlist"], False)
    check("no three-choice offer", cfg["gold_effects"]["choice_offer"], False)
    check("no first-gold effect choice", cfg["gold_effects"]["first_gold_effect_choice"], False)
    for quality in QUALITIES:
        check(f"first-state table matches base {quality}", quality_probabilities((0, 0, True), cfg)[quality], cfg["base_weights"][quality] / 100)
    for novice in (False, True):
        for g in range((cfg["pity"]["first_gold"] if novice else cfg["pity"]["gold_hard"])):
            for p in range(cfg["pity"]["purple_or_better"]):
                probabilities = quality_probabilities((g, p, novice), cfg)
                check(f"probability conservation {novice}/{g}/{p}", sum(probabilities.values()), 1)
                check(f"nonnegative probabilities {novice}/{g}/{p}", all(0 <= v <= 1 for v in probabilities.values()))
    check("gold priority over purple guard", quality_probabilities((29, 9, False), cfg)["gold"], 1)
    check("purple guard keeps natural gold4%", quality_probabilities((0, 9, False), cfg)["gold"], .04)
    check("purple guard redirects nongold96%", quality_probabilities((0, 9, False), cfg)["purple"], .96)
    check("gold resets both quality counters", transition((8, 8, True), "gold"), (0, 0, False))
    check("purple leaves gold progression", transition((8, 8, True), "purple"), (9, 0, True))
    check("twentieth gold chance stays4%", gold_probability(19, False, cfg), .04)
    check("twenty-first chance is12%", gold_probability(20, False, cfg), .12)
    check("twenty-ninth chance is76%", gold_probability(28, False, cfg), .76)
    check("thirtieth is certain", gold_probability(29, False, cfg), 1)
    check("newcomer tenth is certain", gold_probability(9, True, cfg), 1)
    class FixedRng:
        def __init__(self, value):
            self.value = value

        def random(self):
            return self.value

    check("zero RNG endpoint cannot select zero-weight green at hard gold", sample_draw((29, 9, False), cfg, FixedRng(0))[0], "gold")
    check("zero RNG endpoint respects first-gold guarantee", sample_draw((9, 0, True), cfg, FixedRng(0))[0], "gold")
    check("zero RNG endpoint at purple guarantee gives purple", sample_draw((0, 9, False), cfg, FixedRng(0))[0], "purple")
    check("near-one RNG endpoint selects gold", sample_draw((0, 0, True), cfg, FixedRng(1 - 2 ** -53))[0], "gold")
    def draw_groups(groups, serialize=False):
        state, sequence, rng = (0, 0, True), [], random.Random(20261019)
        for size in groups:
            for _ in range(size):
                quality, state = sample_draw(state, cfg, rng)
                effect = rng.randrange(len(cfg["gold_effects"]["weights"])) if quality == "gold" else None
                sequence.append((quality, effect))
                if serialize:
                    state = tuple(json.loads(json.dumps(state)))
        return sequence, state

    check("single and three ten-draw batches identical", draw_groups([1] * 30), draw_groups([10, 10, 10]))
    check("saving counters between draws does not lose progress", draw_groups([1] * 30), draw_groups([1] * 30, serialize=True))
    check("early first gold removes novice promise", gold_probability(7, transition((1, 0, True), "gold")[2], cfg), .04)
    if any(not c["pass"] for c in validation):
        print(json.dumps([c for c in validation if not c["pass"]], ensure_ascii=True))
        raise SystemExit("Selection-rule validation failed")

    first, steady = cycle_exact(cfg, True), cycle_exact(cfg, False)
    chance = cfg["base_weights"]["gold"] / 100
    check("first gold truncated geometric known mean", first["mean"], (1 - (1 - chance) ** cfg["pity"]["first_gold"]) / chance)
    check("first cycle expected quality counts sum to expected draws", sum(first["expected_counts"].values()), first["mean"])
    check("steady cycle expected quality counts sum to expected draws", sum(steady["expected_counts"].values()), steady["mean"])
    check("one guaranteed gold per full cycle", steady["expected_counts"]["gold"], 1)
    check("effective quality rates sum to1", sum(steady["effective_rates"].values()), 1)
    for label, result in (("first", first), ("steady", steady)):
        check(f"{label} cycle fully terminates", result["remaining_mass"], 0)
        check(f"{label} PMF normalized", sum(result["pmf"].values()), 1)
    zero_chance = deepcopy(cfg)
    zero_chance["base_weights"] = {"green": 100, "blue": 0, "purple": 0, "gold": 0}
    zero_chance["pity"]["gold_soft_start"] = 100
    zero_chance["pity"]["gold_soft_increment"] = 0
    check("zero natural gold still stops at hard30", cycle_exact(zero_chance)["mean"], 30)
    check("zero natural rare still gives two purples before hard gold", cycle_exact(zero_chance)["expected_counts"]["purple"], 2)
    certain = deepcopy(cfg)
    certain["pity"]["gold_hard"] = 1
    check("certain gold cycle is one", cycle_exact(certain)["mean"], 1)

    waits = {goal: core_wait_exact(cfg, goal) for goal in ("any", "specified", "all")}
    n = len(cfg["gold_effects"]["weights"])
    harmonic = sum(1 / k for k in range(1, n + 1))
    check("first-any distribution agrees with renewal", waits["any"]["mean"], first["mean"])
    check("specified core mean agrees with geometric gold count", waits["specified"]["mean"], first["mean"] + (n - 1) * steady["mean"])
    check("all8 collection mean agrees with coupon collector", waits["all"]["mean"], first["mean"] + (n * harmonic - 1) * steady["mean"])
    check("specified core has no quality-derived hard maximum", waits["specified"]["guaranteed_maximum"], None)
    for goal, result in waits.items():
        check(f"{goal} absorption plus residual conserved", sum(result["pmf"].values()) + result["residual_probability"], 1)
        check(f"{goal} exact tail converged", result["residual_probability"] < cfg["exact"]["tail_tolerance"])
    check("single named core base chance .5%", chance / n, .005)
    check("one exact3-affix combination in56", math.comb(cfg["ordinary_affixes"]["pool_size"], 3), 56)

    exposures = quality_exposure(cfg, sorted(set(cfg["exact"]["exposures"] + [cfg["monte_carlo"]["draws_per_account"]])))
    for draws, snapshot in exposures.items():
        check(f"exposure state mass conserved {draws}", snapshot["state_mass"], 1)
        check(f"exposure reward count conserved {draws}", sum(snapshot["expected_counts"].values()), draws)
    incomes = {str(c): projected_income(c, sources) for c in cfg["income_projection"]["cleared_room_paths"]}
    incomes["future60_formal_reference"] = projected_income(60, sources, formal_bosses=True)
    check("projection15 no imaginary boss", incomes["15"], 15)
    check("projection30 no imaginary boss", incomes["30"], 45)
    check("projection45 no imaginary boss", incomes["45"], 75)
    check("future60 model only includes real-planned boss bonuses", incomes["future60_formal_reference"], 150)
    check("actual45 income still flagged disabled", cfg["income_projection"]["actual_route_income_enabled"], False)
    progression = sources["meta"]["progression"]
    upgrade = [progression["upgrade_cost_by_current_level"][str(k)] for k in (1, 2)]
    purchases = {"draw_only": [], "first_catalyst_to3": upgrade,
                 "both_catalysts_to3": upgrade + [progression["unlock_cost"]] + upgrade}
    forecasts = {}
    for room in cfg["income_projection"]["cleared_room_paths"]:
        for policy, queue in purchases.items():
            result = ledger(cfg, incomes[str(room)], queue, waits)
            forecasts[f"clear{room}/{policy}"] = result
            for row in result["rows"]:
                check(f"dust conservation {room}/{policy}/{row['session']}", row["earned"] + cfg["income_projection"]["starting_dust"], row["balance"] + row["draw_spend"] + row["catalyst_spend"])
                check(f"nonnegative stock {room}/{policy}/{row['session']}", row["balance"] >= 0)
    check("one catalyst costs60", sum(purchases["first_catalyst_to3"]), 60)
    check("two catalysts cost140", sum(purchases["both_catalysts_to3"]), 140)
    check("three early9-room runs afford5draws with2left", forecasts["clear9/draw_only"]["rows"][2]["balance"], 2)
    check("three early9-room runs number of draws", forecasts["clear9/draw_only"]["rows"][2]["total_draws"], 5)

    monte_carlo = []
    draws = cfg["monte_carlo"]["draws_per_account"]
    expected_golds = exposures[draws]["expected_counts"]["gold"]
    for seed in cfg["monte_carlo"]["seeds"]:
        observed = sample_batch(cfg, seed)
        monte_carlo.append(observed)
        check(f"sample has no guarantee violations seed{seed}", observed["guarantee_violations"], 0)
        sem = math.sqrt(first["variance"] / observed["accounts"])
        check(f"first-gold sample agrees with exact within6SE seed{seed}", abs(observed["mean_first_gold"] - first["mean"]) <= 6 * sem)
        check(f"finite-horizon gold sample agrees with exact within6SE seed{seed}", abs(observed["mean_gold_per_account"] - expected_golds) <= 6 * observed["gold_count_stdev"] / math.sqrt(observed["accounts"]))
        for quality in QUALITIES:
            expected = exposures[draws]["expected_counts"][quality] / draws
            check(f"finite-horizon {quality} sample agrees with exact within6SE seed{seed}", abs(observed["observed_quality_rates"][quality] - expected) <= 6 * observed["quality_rate_standard_errors"][quality] + 1 / (draws * observed["accounts"]))
        for goal, key in (("specified", "specified_core_probability"), ("all", "all_core_probability")):
            expected = cdf_at(waits[goal], draws)
            error = 6 * math.sqrt(expected * (1 - expected) / observed["accounts"]) + 1 / observed["accounts"]
            check(f"{goal} sample agrees with exact within6SE seed{seed}", abs(observed[key] - expected) <= error)

    sweeps = []
    for cost in cfg["sweeps"]["draw_cost"]:
        sweeps.append({"axis": "draw_cost", "value": cost, "draws_per75dust": incomes["45"] / cost,
                       "mean_dust_first_gold": first["mean"] * cost, "max_dust_first_gold": first["maximum"] * cost,
                       "mean_dust_regular_gold": steady["mean"] * cost, "max_dust_regular_gold": steady["maximum"] * cost})
    for axis, entries in (("base_tables", cfg["sweeps"]["base_tables"]), ("hard_gold", cfg["sweeps"]["hard_gold"]), ("soft_increment", cfg["sweeps"]["soft_increment"])):
        for value in entries:
            candidate = deepcopy(cfg)
            if axis == "base_tables":
                candidate["base_weights"] = value
            elif axis == "hard_gold":
                candidate["pity"].update(value)
            else:
                candidate["pity"]["gold_soft_increment"] = value
            result = cycle_exact(candidate)
            sweeps.append({"axis": axis, "value": value, "mean_gold_draws": result["mean"],
                           "effective_quality_rates": result["effective_rates"], "p90": result["p90"], "p99": result["p99"]})
    targets = {
        "first_gold_max_draws": first["maximum"], "steady_mean_gold_draws": steady["mean"],
        "steady_mean_gold_per_projected_45_clear": incomes["45"] / cfg["draw_cost"] / steady["mean"],
        "purple_or_gold_max_drought": cfg["pity"]["purple_or_better"] - 1
    }
    target_results = []
    for name, target in cfg["targets"].items():
        actual = targets[name]
        ok = target[0] <= actual <= target[1] if isinstance(target, list) else actual == target
        target_results.append({"name": name, "actual": actual, "target": target, "status": "within" if ok else "outside"})
    after = {str(p.relative_to(ROOT)).replace("\\", "/"): sha(p) for p in source_paths.values()}
    check("all read source bytes unchanged", hashes, after)
    report = {"model_version": MODEL_VERSION, "model_sha256": sha(__file__), "parameter_sha256": sha(args.parameters),
              "model_changes": ["1.0: exact renewal, core collection and ledger model; corrected sampler variable before first successful output", "1.1: explicit zero-weight endpoint cases, single/batch/save counter equivalence and finite-horizon quality marginal cross-checks"],
              "source_sha256": hashes, "parameters": cfg, "validation": validation, "targets": target_results,
              "first_gold": first, "steady_gold": steady, "core_waits": waits, "quality_exposures": exposures,
              "income_projections": incomes, "catalyst_purchase_queues": purchases, "economy_forecasts": forecasts,
              "monte_carlo": monte_carlo, "sweeps": sweeps,
              "omissions": ["Projected income is not currently enabled in the45-room route", "No salvage, recycling refunds, affix reforge, free starting pulls or old-save refunds modeled",
                            "Fully random equal-weight gold effects; no effect guarantee despite rarity guarantees", "Desired effect is not a perfect3-affix gem; no combat simulation or playtest utility inferred",
                            "Income paths use identical cleared-room depth per session; no player skill/time forecast or room-farming optimum inferred"]}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    summary = ["# Gem draw probability and economy proposal", "", f"Model: {MODEL_VERSION}",
               f"Checks: {sum(v['pass'] for v in validation)}/{len(validation)}", "",
               f"First gold mean {first['mean']:.6f}, median {first['p50']}, P90 {first['p90']}, max {first['maximum']}",
               f"Regular gold mean {steady['mean']:.6f}, median {steady['p50']}, P90 {steady['p90']}, max {steady['maximum']}",
               "", "## Long-run effective quality rates", ""]
    summary += [f"- {q}: {steady['effective_rates'][q]:.6%}" for q in QUALITIES]
    summary += ["", "## Fully random core acquisition", "", "| Goal | Mean draws | Median | P90 | P95 | P99 | Guaranteed maximum |", "|---|---|---|---|---|---|---|"]
    summary += [f"| {goal} | {r['mean']:.4f} | {r['p50']} | {r['p90']} | {r['p95']} | {r['p99']} | {r['guaranteed_maximum']} |" for goal, r in waits.items()]
    summary += ["", "## Price comparison", "", "| Cost | Draws per75dust | Mean dust first gold | Max dust first gold | Mean dust regular gold | Max dust regular gold |", "|---|---|---|---|---|---|"]
    summary += [f"| {r['value']} | {r['draws_per75dust']:.2f} | {r['mean_dust_first_gold']:.3f} | {r['max_dust_first_gold']} | {r['mean_dust_regular_gold']:.3f} | {r['max_dust_regular_gold']} |" for r in sweeps if r["axis"] == "draw_cost"]
    summary += ["", "## Projected session budget (no catalyst spending)", "", "| Clear depth | Dust/session | Mean first-gold session | Latest first-gold session |", "|---|---|---|---|"]
    summary += [f"| {room} | {incomes[str(room)]} | {forecasts[f'clear{room}/draw_only']['mean_session_to_first_gold']:.4f} | {forecasts[f'clear{room}/draw_only']['guaranteed_session_to_first_gold']} |" for room in cfg["income_projection"]["cleared_room_paths"]]
    summary += ["", "## Omissions", ""] + [f"- {v}" for v in report["omissions"]]
    (args.output / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    failures = [v for v in validation if not v["pass"]]
    print(json.dumps({"model": MODEL_VERSION, "checks": len(validation), "failed": len(failures),
                      "first_gold_mean": first["mean"], "steady_gold_mean": steady["mean"],
                      "effective_gold_rate": steady["effective_rates"]["gold"], "targets": target_results,
                      "output": str(args.output)}, ensure_ascii=True))
    if failures:
        print(json.dumps(failures, ensure_ascii=True))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
