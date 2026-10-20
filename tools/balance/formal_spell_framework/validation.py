"""Fidelity, analytic checks and stochastic cross-checks for the proposal model."""
from __future__ import annotations

from itertools import permutations
from math import comb, isclose
from random import Random

from model import DrawRule, draw_offer, eligible_ids, exact_offer_distribution, primary_probability


def validate(parameters: dict, sources: dict, native: dict) -> dict:
    results: list[dict] = []

    def check(ok: bool, name: str, details=None):
        results.append({"name": name, "passed": bool(ok), "details": details})

    base, meta, route = sources["base"], sources["meta"], sources["route"]
    slots = int(base["limits"]["slots"])
    max_level = int(base["limits"]["spell_level"])
    offer_count = int(meta["spell_sampling_assumptions"]["offer_size"])
    check(slots == 8 and max_level == 3 and offer_count == 3, "current source contract is 8 slots, 3 levels, 3 unique cards")
    check(len(base["spells"]) == 10, "current runtime remains ten fire spells")
    check(meta["catalyst_weight_by_level"] == [1.5, 1.75, 2.0], "old source multiplicative weights read, not invented")
    check(meta["spell_sampling_assumptions"]["eligibility_before_weighting"], "actual meta says eligibility before bias")
    check(meta["spell_sampling_assumptions"]["unique_within_offer"], "actual meta says without replacement within screen")
    check(meta["spell_sampling_assumptions"]["affects_owned_spell_upgrades"], "actual meta bias includes owned upgrades")
    check(not meta["spell_sampling_assumptions"]["affects_initial_offer"], "current old bias does not alter initial choice")
    check(meta["progression"]["first_choice_free_per_kind"] and meta["equipment"]["catalyst_slots"] == 1, "current first-free and one-equipped contract read without opening a save")
    check(len(route["reward_rooms"]) == 36 and route["reward_rooms"][22] == 28, "actual 45-route has 36 books and the 23rd at room28")
    check(len(route["reward_rooms"][23:]) == 13, "23 growth still leaves 13 actual book nodes")
    check(native["failures"] == 0 and native["source_stable"], "read-only actual Godot baseline bridge succeeds")

    source_ids = list(base["spells"])
    native_comparisons: list[dict] = []
    for case in native["cases"]:
        owned = case["owned"]
        expected_legal = [spell for spell in source_ids if (owned.get(spell, 0) < max_level if spell in owned else len(owned) < slots)]
        check(case["legal"] == expected_legal, f"actual core legal pool: {case['state']} level{case['level']}")
        expected_weight = meta["catalyst_weight_by_level"][case["level"] - 1] if case["level"] else 1.0
        expected_weights = {spell: expected_weight if case["level"] and spell in case["primary_ids"] else 1.0 for spell in source_ids}
        check(case["weights"] == expected_weights, f"actual core old weights: {case['state']} level{case['level']}")
        primary = sum(spell in case["primary_ids"] for spell in expected_legal)
        other = len(expected_legal) - primary
        exact = exact_offer_distribution(primary, other, offer_count, DrawRule("old_weight", expected_weight))
        observed = [count / case["trials"] for count in case["histogram"]]
        error = max(abs(observed[k] - (exact[k] if k < len(exact) else 0.0)) for k in range(4))
        check(error < 0.02, f"actual Godot histogram vs exact weighted DP: {case['state']} level{case['level']}", {"max_absolute_error": error})
        native_comparisons.append({"state": case["state"], "level": case["level"], "n": case["trials"], "exact": list(exact), "observed": observed, "maximum_absolute_error": error})

    # Independent finite-item permutation enumerator checks the count-collapsed
    # old-weight model rather than repeating its DP implementation.
    for m, o, weight in [(3, 7, 1.5), (3, 7, 2.0), (2, 2, 1.0)]:
        weights = [weight] * m + [1.0] * o
        histogram = [0.0] * 4
        for ordered in permutations(range(m + o), 3):
            probability = 1.0
            total = sum(weights)
            for spell in ordered:
                probability *= weights[spell] / total
                total -= weights[spell]
            histogram[sum(spell < m for spell in ordered)] += probability
        exact = exact_offer_distribution(m, o, 3, DrawRule("old_weight", weight))
        check(max(abs(a - b) for a, b in zip(histogram, exact)) < 1e-12, f"independent item enumeration matches group DP ({m},{o},{weight})")

    uniform = exact_offer_distribution(10, 50, 3, DrawRule("uniform"))
    hypergeometric = [comb(10, k) * comb(50, 3 - k) / comb(60, 3) for k in range(4)]
    check(max(abs(a - b) for a, b in zip(uniform, hypergeometric)) < 1e-12, "uniform six-school case matches exact hypergeometric")
    check(isclose(sum(k * p for k, p in enumerate(uniform)), 0.5), "uniform six-school expected primary cards is 3*10/60=0.5")
    fixed = exact_offer_distribution(10, 50, 3, DrawRule("fixed", 0.4))
    check(all(isclose(fixed[k], comb(3, k) * 0.4 ** k * 0.6 ** (3 - k)) for k in range(4)), "fixed40 matches binomial only while neither bucket can empty in3 draws")
    check(all(isclose(a, b, abs_tol=1e-12) for a, b in zip(exact_offer_distribution(1, 2, 3, DrawRule("adaptive", 0.52)), (0.0, 1.0, 0.0, 0.0))), "when only3 legal IDs remain the whole offer is fixed, no invented bias effect")
    check(exact_offer_distribution(0, 4, 3, DrawRule("adaptive", 0.52)) == (1.0, 0.0, 0.0, 0.0), "empty primary falls back to other bucket")
    check(exact_offer_distribution(4, 0, 3, DrawRule("adaptive", 0.52)) == (0.0, 0.0, 0.0, 1.0), "empty other falls back to primary bucket")
    check(exact_offer_distribution(0, 0, 3, DrawRule("adaptive", 0.52)) == (1.0,), "all-full pool returns no offer, not an empty choice")
    check(len(eligible_ids(60, {i: 1 for i in range(8)}, 8, 3)) == 8, "full slots suppress52 new IDs, retaining8 upgrade IDs")
    check(eligible_ids(60, {i: 3 for i in range(8)}, 8, 3) == [], "full8 at3 exhaust all60-spell eligibility")
    check(len(eligible_ids(60, {0: 3}, 8, 3)) == 59, "maxed owned spell filtered before sampling")
    check(0 in eligible_ids(60, {0: 2}, 8, 3), "owned level2 remains legal at the same ID granularity")

    adaptive_monotonic = True
    for m in range(1, 11):
        for o in range(1, 51):
            q = m / (m + o)
            ps = [primary_probability(m, o, DrawRule("adaptive", b)) for b in parameters["recommended_level_strengths"]]
            adaptive_monotonic &= q < ps[0] < ps[1] < ps[2] < 1
    check(adaptive_monotonic, "adaptive three levels strictly raise first-draw odds in all500 nonempty pool-count cases")
    check(primary_probability(10, 10, DrawRule("fixed", 0.4)) < 0.5, "regression: rejected fixed40 lowers two-school fresh primary exposure")
    check(primary_probability(6, 2, DrawRule("fixed", 0.6)) < 0.75, "regression: rejected fixed60 lowers full-slot6/2 primary upgrade exposure")

    mc_cases = [(10, 50, DrawRule("uniform")), (10, 50, DrawRule("fixed", 0.4)),
                (10, 50, DrawRule("adaptive", 0.28)), (6, 2, DrawRule("adaptive", 0.52)),
                (1, 50, DrawRule("adaptive", 0.52)), (2, 50, DrawRule("adaptive", 0.4))]
    mc_comparisons: list[dict] = []
    trials = int(parameters["offer_validation_trials"])
    for index, (m, o, rule) in enumerate(mc_cases):
        rng = Random(20261017 + index)
        histogram = [0] * 4
        valid = True
        for _ in range(trials):
            offered = draw_offer(list(range(m + o)), m, rule, rng, 3)
            valid &= len(offered) == len(set(offered)) == 3
            histogram[sum(spell < m for spell in offered)] += 1
        expected = exact_offer_distribution(m, o, 3, rule)
        observed = [count / trials for count in histogram]
        error = max(abs(a - b) for a, b in zip(expected, observed))
        check(valid and error < parameters["guardrails"]["maximum_sampling_error"], f"Python MC vs exact DP ({m},{o},{rule.label})", {"n": trials, "max_absolute_error": error})
        mc_comparisons.append({"primary": m, "other": o, "rule": rule.label, "n": trials, "seed": 20261017 + index, "exact": list(expected), "observed": observed, "maximum_absolute_error": error})
    return {"checks": len(results), "failures": sum(not row["passed"] for row in results), "cases": results,
            "actual_runtime_fidelity": native_comparisons, "monte_carlo_cross_checks": mc_comparisons}
