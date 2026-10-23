"""Exact sequential offer probabilities and bounded 52-book choice trajectories.

No combat, player utility, or Godot PCG trace claim. The six real school sources
and authoritative route reward nodes are loaded by run.py.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
import math
import random


@dataclass(frozen=True)
class Rule:
    mode: str
    strength: float = 0.0
    owned_weight: float = 1.0
    legacy_weight: float = 1.0


def probabilities(pool, owned, schools, main, rule):
    """Per-ID probability at this card, after legal filtering and removals."""
    if not pool:
        return {}
    weight = {s: (rule.owned_weight if s in owned else 1.0) for s in pool}
    if rule.mode == "legacy":
        weight = {s: w * (rule.legacy_weight if schools[s] == main else 1.0)
                  for s, w in weight.items()}
        total = sum(weight.values())
        return {s: w / total for s, w in weight.items()}
    main_ids = [s for s in pool if schools[s] == main]
    other_ids = [s for s in pool if schools[s] != main]
    main_w = sum(weight[s] for s in main_ids)
    other_w = sum(weight[s] for s in other_ids)
    q = main_w / (main_w + other_w)
    p = q + (1 - q) * rule.strength if main_ids and other_ids else q
    result = {}
    for s in main_ids:
        result[s] = p * weight[s] / main_w
    for s in other_ids:
        result[s] = (1 - p) * weight[s] / other_w
    return result


def offer(pool, owned, schools, main, rule, rng, size=3):
    pool = list(pool)
    result = []
    for _ in range(min(size, len(pool))):
        probs = probabilities(pool, owned, schools, main, rule)
        roll = rng.random()
        selected = pool[-1]
        for s in pool:
            roll -= probs[s]
            if roll < 0:
                selected = s
                break
        result.append(selected)
        pool.remove(selected)
    return result


def exact_counts(main_count, other_count, rule, size=3):
    """Exact DP for equal-weight IDs, returning count of main cards."""
    dist = {(main_count, other_count, 0): 1.0}
    for _ in range(min(size, main_count + other_count)):
        new = defaultdict(float)
        for (m, o, count), mass in dist.items():
            if not m:
                p = 0.0
            elif not o:
                p = 1.0
            elif rule.mode == "legacy":
                p = m * rule.legacy_weight / (m * rule.legacy_weight + o)
            else:
                q = m / (m + o)
                p = q + (1 - q) * rule.strength
            if m:
                new[(m - 1, o, count + 1)] += mass * p
            if o:
                new[(m, o - 1, count)] += mass * (1 - p)
        dist = new
    result = defaultdict(float)
    for (_, _, count), mass in dist.items():
        result[count] += mass
    return dict(result)


def exact_weighted_counts(counts, categories, rule, size=3):
    """Four-category exact DP, including owned-upgrade weights after removals."""
    dist = {(tuple(counts), 0): 1.0}
    for _ in range(min(size, sum(counts))):
        new = defaultdict(float)
        for (state, main_drawn), mass in dist.items():
            weights = [count * (rule.owned_weight if owned else 1.0)
                       for count, (_, owned) in zip(state, categories)]
            main_w = sum(w for w, (main, _) in zip(weights, categories) if main)
            other_w = sum(weights) - main_w
            q = main_w / (main_w + other_w)
            p = q + (1-q) * rule.strength if main_w and other_w else q
            if rule.mode == "legacy":
                p = main_w * rule.legacy_weight / (main_w * rule.legacy_weight + other_w)
            for i, (count, w, (main, _)) in enumerate(zip(state, weights, categories)):
                if not count: continue
                probability = (p * w / main_w) if main else ((1-p) * w / other_w)
                after = list(state)
                after[i] -= 1
                new[(tuple(after), main_drawn + int(main))] += mass * probability
        dist = new
    result = defaultdict(float)
    for (_, k), mass in dist.items(): result[k] += mass
    return dict(result)


def eligible(ids, owned, requirements):
    return [s for s in ids if owned.get(s, 0) < 3 and
            (s in owned or not requirements.get(s) or
             any(source in owned for source in requirements[s]))]


def select(cards, owned, schools, main, secondary, policy, rng):
    """Select ID/replacement or legal all-new full-slot skip, without rerolls."""
    counts = {main: sum(schools[s] == main for s in owned),
              secondary: sum(schools[s] == secondary for s in owned)}
    full = len(owned) == 8
    if policy == "upgrade_priority":
        upgrades = [s for s in cards if s in owned]
        if upgrades:
            best = max((owned[s], schools[s] == main) for s in upgrades)
            choice = rng.choice([s for s in upgrades if (owned[s], schools[s] == main) == best])
            return choice, None
        if full:
            return None, None
        choice = rng.choice([s for s in cards if schools[s] == main] or cards)
        return choice, None
    def wanted_new(s):
        if s in owned:
            return False
        if policy == "main_priority":
            return schools[s] == main
        return schools[s] in counts and counts[schools[s]] < 4
    def victim(s):
        options = [old for old in owned if schools[old] != schools[s] and
                   (schools[old] not in counts or
                    (policy == "main_priority" and schools[old] != main) or
                    (policy == "dual_four_four" and counts[schools[old]] > 4))]
        if not options:
            return None
        return min(options, key=lambda old: (owned[old], list(owned).index(old)))
    candidates = []
    for s in cards:
        replacement = victim(s) if full and wanted_new(s) else None
        can_learn = not full or replacement is not None
        if s in owned:
            if policy == "main_priority":
                score = (2 if schools[s] == main else 0, 1, owned[s])
            else:
                score = (1 if schools[s] in counts else 0, 1, owned[s])
            candidates.append((score, s, None))
        elif can_learn:
            if policy == "main_priority":
                score = (2 if wanted_new(s) else -1, 0, 0)
            else:
                score = (2 if wanted_new(s) else -1, 0, 0)
            candidates.append((score, s, replacement))
    if not candidates:
        assert full and all(s not in owned for s in cards)
        return None, None
    best = max(row[0] for row in candidates)
    _, choice, old = rng.choice([row for row in candidates if row[0] == best])
    return choice, old


def trajectory(ids, schools, requirements, main, secondary, starters, rule, policy, rooms, seed):
    rng = random.Random(seed)
    owned = {rng.choice(starters[main]): 1}
    milestones = {k: None for k in ["resonance", "first_level3", "eight_slots", "eight_level3", "dual_four_four"]}
    drought = longest_drought = skipped = replacements = upgrades = 0
    snapshots = {}
    for book, room in enumerate(rooms, 1):
        pool = eligible(ids, owned, requirements)
        cards = offer(pool, owned, schools, main, rule, rng)
        assert len(cards) == min(3, len(pool)) and len(set(cards)) == len(cards)
        has_upgrade = any(s in owned for s in cards)
        if any(level < 3 for level in owned.values()):
            drought = 0 if has_upgrade else drought + 1
            longest_drought = max(longest_drought, drought)
        else:
            drought = 0
        choice, old = select(cards, owned, schools, main, secondary, policy, rng) if cards else (None, None)
        if choice is None:
            skipped += 1
        elif choice in owned:
            owned[choice] += 1
            upgrades += 1
        else:
            if old is not None:
                owned.pop(old)
                replacements += 1
            owned[choice] = 1
        assert len(owned) <= 8 and all(1 <= level <= 3 for level in owned.values())
        main_count = sum(schools[s] == main for s in owned)
        secondary_count = sum(schools[s] == secondary for s in owned)
        tests = {"resonance": main_count >= 3, "first_level3": 3 in owned.values(),
                 "eight_slots": len(owned) == 8, "eight_level3": len(owned) == 8 and sum(owned.values()) == 24,
                 "dual_four_four": main_count == 4 and secondary_count == 4}
        for key, value in tests.items():
            if value and milestones[key] is None:
                milestones[key] = book
        if book in [8, 13, 16, 26, 39, 52]:
            snapshots[str(book)] = {"levels": sum(owned.values()), "main_count": main_count, "slots": len(owned)}
    return {**milestones, "final_levels": sum(owned.values()), "final_main": main_count,
            "final_secondary": secondary_count, "max_upgrade_drought": longest_drought,
            "skipped": skipped, "replacements": replacements, "upgrades": upgrades, "snapshots": snapshots}


def percentile(values, fraction):
    values = sorted(values)
    rank = (len(values) - 1) * fraction
    lo, hi = math.floor(rank), math.ceil(rank)
    return values[lo] * (hi - rank) + values[hi] * (rank - lo) if hi != lo else values[lo]


def summarize(rows, horizon):
    result = {"trials": len(rows)}
    for key in ["final_levels", "final_main", "final_secondary", "max_upgrade_drought", "skipped", "replacements", "upgrades"]:
        values = [r[key] for r in rows]
        result[key] = {"mean": sum(values) / len(values), **{f"p{int(q*100)}": percentile(values, q) for q in [.1,.5,.9,.95]}}
    for key in ["resonance", "first_level3", "eight_slots", "eight_level3", "dual_four_four"]:
        values = [r[key] for r in rows if r[key] is not None]
        result[key] = {"completion_rate": len(values) / len(rows), "by_book8": sum(v <= 8 for v in values) / len(rows),
                       **({f"p{int(q*100)}_among_completed": percentile(values, q) for q in [.1,.5,.9]} if values else {})}
    result["snapshots"] = {book: {key: sum(row["snapshots"][book][key] for row in rows) / len(rows)
                                  for key in ["levels", "main_count", "slots"]}
                           for book in rows[0]["snapshots"]}
    for book in result["snapshots"]:
        for key in ["levels", "main_count", "slots"]:
            values = [row["snapshots"][book][key] for row in rows]
            for q in [.1,.5,.9]: result["snapshots"][book][key + "_p" + str(int(q*100))] = percentile(values, q)
    return result
