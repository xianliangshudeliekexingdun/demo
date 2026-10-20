"""Small pure draw/progression model, separate from runtime and file loading."""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from math import sqrt
from random import Random
from statistics import mean, stdev


@dataclass(frozen=True)
class DrawRule:
    kind: str
    value: float = 0.0

    @property
    def label(self) -> str:
        return self.kind if self.kind == "uniform" else f"{self.kind}:{self.value:g}"


def primary_probability(primary: int, other: int, rule: DrawRule) -> float:
    if primary < 0 or other < 0:
        raise ValueError("pool counts cannot be negative")
    if not primary:
        return 0.0
    if not other:
        return 1.0
    q = primary / (primary + other)
    if rule.kind == "uniform":
        return q
    if rule.kind == "fixed":
        if not 0 <= rule.value <= 1:
            raise ValueError("fixed probability out of bounds")
        return rule.value
    if rule.kind == "adaptive":
        if not 0 <= rule.value <= 1:
            raise ValueError("adaptive strength out of bounds")
        return q + (1 - q) * rule.value
    if rule.kind == "old_weight":
        if rule.value <= 0:
            raise ValueError("weight must be positive")
        return primary * rule.value / (primary * rule.value + other)
    raise ValueError(rule.kind)


def exact_offer_distribution(primary: int, other: int, count: int, rule: DrawRule) -> tuple[float, ...]:
    """Exact group-count DP; recalculates the conditional rule after each draw."""
    if primary < 0 or other < 0 or count < 0:
        raise ValueError("counts must be nonnegative")
    draws = min(count, primary + other)

    @lru_cache(None)
    def visit(m: int, o: int, left: int) -> tuple[float, ...]:
        if not left:
            return (1.0,)
        result = [0.0] * (left + 1)
        probability = primary_probability(m, o, rule)
        if m:
            for hits, chance in enumerate(visit(m - 1, o, left - 1)):
                result[hits + 1] += probability * chance
        if o:
            for hits, chance in enumerate(visit(m, o - 1, left - 1)):
                result[hits] += (1 - probability) * chance
        return tuple(result)

    return visit(primary, other, draws)


def offer_metrics(primary: int, other: int, count: int, rule: DrawRule) -> dict:
    distribution = exact_offer_distribution(primary, other, count, rule)
    draws = min(count, primary + other)
    return {
        "primary_legal": primary, "other_legal": other, "draws": draws,
        "rule": rule.label, "first_draw_primary": primary_probability(primary, other, rule),
        "distribution": list(distribution),
        "at_least_one_primary": 1 - distribution[0] if draws else 0.0,
        "all_primary": distribution[draws] if draws else 0.0,
        "at_least_one_other": 1 - distribution[draws] if draws else 0.0,
        "both_groups": 1 - distribution[0] - distribution[draws] if draws else 0.0,
        "expected_primary_cards": sum(k * chance for k, chance in enumerate(distribution)),
    }


def draw_offer(eligible: list[int], school_size: int, rule: DrawRule, rng: Random, count: int) -> list[int]:
    primary = [spell for spell in eligible if spell < school_size]
    other = [spell for spell in eligible if spell >= school_size]
    offered: list[int] = []
    for _ in range(min(count, len(eligible))):
        chance = primary_probability(len(primary), len(other), rule)
        # RNG parity with Godot is not claimed: this verifies distributions.
        bucket = primary if rng.random() < chance else other
        index = rng.randrange(len(bucket))
        offered.append(bucket.pop(index))
    return offered


def eligible_ids(total: int, owned: dict[int, int], slots: int, max_level: int) -> list[int]:
    capacity = len(owned) < slots
    return [spell for spell in range(total) if (owned.get(spell, 0) < max_level if spell in owned else capacity)]


def choose(offered: list[int], owned: dict[int, int], school_size: int, policy: str, rng: Random, slots: int) -> int:
    main_slots = sum(spell < school_size for spell in owned)
    other_slots = len(owned) - main_slots
    target_main = slots // 2
    target_other = slots - target_main

    def score(spell: int) -> tuple:
        primary = spell < school_size
        level = owned.get(spell, 0)
        if policy == "primary_first":
            return (primary,)
        if policy == "learn_first":
            return (level == 0, primary)
        if policy == "upgrade_first":
            return (level > 0, primary, level)
        if policy == "mixed_four_four":
            deficit = (target_main - main_slots) if primary else (target_other - other_slots)
            return (level == 0 and deficit > 0, deficit if level == 0 and deficit > 0 else -1, level > 0, level)
        raise ValueError(policy)

    scores = [score(spell) for spell in offered]
    best = max(scores)
    return rng.choice([spell for spell, value in zip(offered, scores) if value == best])


def composition(owned: dict[int, int], school_size: int) -> dict:
    main = sum(spell < school_size for spell in owned)
    return {
        "primary_slots": main, "other_slots": len(owned) - main, "slots": len(owned),
        "primary_levels": sum(level for spell, level in owned.items() if spell < school_size),
        "other_levels": sum(level for spell, level in owned.items() if spell >= school_size),
        "schools_present": len({spell // school_size for spell in owned}),
    }


def one_trajectory(schools: int, school_size: int, rule: DrawRule, policy: str,
                   seed: int, slots: int, max_level: int, offers: int,
                   book_rooms: list[int], starter: int = 0, trace: bool = False) -> dict:
    rng = Random(seed)
    owned: dict[int, int] = {starter: 1}
    growth_count = 0
    first_eight: dict = {}
    first_capacity: dict = {}
    first_capacity_growth = 0
    offer_primary = 0
    offer_other = 0
    early_primary = 0
    early_other = 0
    longest_primary_drought = 0
    longest_other_drought = 0
    primary_drought = 0
    other_drought = 0
    skipped = 0
    trace_rows: list[dict] = []
    legal_violation = False
    for room in book_rooms:
        legal = eligible_ids(schools * school_size, owned, slots, max_level)
        if not legal:
            skipped += 1
            continue
        offered = draw_offer(legal, school_size, rule, rng, offers)
        if len(offered) != len(set(offered)) or any(spell not in legal for spell in offered):
            legal_violation = True
        has_primary = any(spell < school_size for spell in offered)
        has_other = any(spell >= school_size for spell in offered)
        offer_primary += has_primary
        offer_other += has_other
        primary_drought = 0 if has_primary else primary_drought + 1
        other_drought = 0 if has_other else other_drought + 1
        longest_primary_drought = max(longest_primary_drought, primary_drought)
        longest_other_drought = max(longest_other_drought, other_drought)
        if growth_count < 8:
            early_primary += has_primary
            early_other += has_other
        selected = choose(offered, owned, school_size, policy, rng, slots)
        was_new = selected not in owned
        owned[selected] = owned.get(selected, 0) + 1
        growth_count += 1
        if len(owned) > slots or max(owned.values()) > max_level:
            legal_violation = True
        if growth_count == 8:
            first_eight = composition(owned, school_size)
        if len(owned) == slots and not first_capacity:
            first_capacity = composition(owned, school_size)
            first_capacity_growth = growth_count
        if trace:
            trace_rows.append({"room": room, "growth": growth_count,
                               "offered": offered, "chosen": selected, "new": was_new,
                               "composition": composition(owned, school_size)})
    final = composition(owned, school_size)
    return {
        "first_eight": first_eight, "first_capacity": first_capacity,
        "first_capacity_growth": first_capacity_growth, "final": final,
        "growth_count": growth_count, "skipped_book_nodes": skipped,
        "eligible_final": len(eligible_ids(schools * school_size, owned, slots, max_level)),
        "offer_primary": offer_primary, "offer_other": offer_other,
        "early_primary": early_primary, "early_other": early_other,
        "longest_primary_drought": longest_primary_drought,
        "longest_other_drought": longest_other_drought,
        "legal_violation": legal_violation,
        "owned": owned if trace else {}, "trace": trace_rows,
    }


def distribution(values: list[float]) -> dict:
    ordered = sorted(values)
    count = len(ordered)
    average = mean(ordered)
    sd = stdev(ordered) if count > 1 else 0.0

    def quantile(p: float) -> float:
        # Nearest-rank empirical quantile; discrete slot counts stay discrete.
        from math import ceil
        return ordered[max(0, min(count - 1, ceil(p * count) - 1))]

    return {"n": count, "mean": average, "sd": sd,
            "mean_mc_se": sd / sqrt(count),
            "mean_mc_95_half_width": 1.96 * sd / sqrt(count),
            "p05": quantile(0.05), "p50": quantile(0.5), "p95": quantile(0.95),
            "minimum_observed": ordered[0], "maximum_observed": ordered[-1]}


def aggregate(rows: list[dict], slots: int, max_level: int) -> dict:
    def summarize(key: str, nested: str | None = None) -> dict:
        return distribution([row[nested][key] if nested else row[key] for row in rows])

    result = {
        "trials": len(rows),
        "first_eight_primary_slots": summarize("primary_slots", "first_eight"),
        "first_eight_other_slots": summarize("other_slots", "first_eight"),
        "first_eight_primary_levels": summarize("primary_levels", "first_eight"),
        "growth_to_eight_slots": summarize("first_capacity_growth"),
        "final_primary_slots": summarize("primary_slots", "final"),
        "final_other_slots": summarize("other_slots", "final"),
        "final_schools_present": summarize("schools_present", "final"),
        "early_eight_offer_primary_fraction": distribution([row["early_primary"] / 8 for row in rows]),
        "early_eight_offer_other_fraction": distribution([row["early_other"] / 8 for row in rows]),
        "longest_primary_offer_drought": summarize("longest_primary_drought"),
        "longest_other_offer_drought": summarize("longest_other_drought"),
        "final_primary_slot_histogram": {str(k): sum(row["final"]["primary_slots"] == k for row in rows) for k in range(slots + 1)},
        "all_primary_final_fraction": sum(row["final"]["primary_slots"] == slots for row in rows) / len(rows),
        "at_least_six_primary_final_fraction": sum(row["final"]["primary_slots"] >= 6 for row in rows) / len(rows),
        "mixed_four_four_final_fraction": sum(row["final"]["primary_slots"] == slots // 2 for row in rows) / len(rows),
        "all_trajectories_23_growth": all(row["growth_count"] == slots * max_level - 1 for row in rows),
        "all_trajectories_exhausted": all(row["eligible_final"] == 0 for row in rows),
        "skipped_book_nodes": summarize("skipped_book_nodes"),
        "legal_violation_count": sum(row["legal_violation"] for row in rows),
        "first_capacity_matches_final_count": all(all(row["first_capacity"][key] == row["final"][key] for key in ["primary_slots", "other_slots", "slots", "schools_present"]) for row in rows),
    }
    return result
