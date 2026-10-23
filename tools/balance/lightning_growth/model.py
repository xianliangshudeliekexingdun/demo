"""Design-only lightning event budgets on declared static geometry.

Actors are stationary immortal targets. Maintained conduction represents setup by
an unspecified companion and is explicitly an upper bound, not a free ability.
"""
from __future__ import annotations

import heapq
import math

MODEL_VERSION = "lightning-growth-design-1.0"
EPS = 1e-8


def effective_cd(base, reduction):
    return max(.2, base * (1 - min(.6, max(0, reduction))))


def crit_factor(rate, multiplier):
    return 1 + min(1, max(0, rate)) * (multiplier - 1)


def connection_path(start, positions, marked, cap, base=3.5, both_add=1,
                    mastery_add=0, blocked=()):
    """One path: existing-conductive preference, distance, stable ID; no revisit."""
    visited = [start]
    blocked = {frozenset(pair) for pair in blocked}
    while len(visited) < cap:
        origin = visited[-1]
        candidates = []
        for key in positions:
            if key in visited or frozenset((origin, key)) in blocked:
                continue
            distance = math.dist(positions[origin], positions[key])
            reach = base + (both_add + mastery_add if marked(origin) and marked(key) else 0)
            if distance <= reach + EPS:
                candidates.append((not marked(key), distance, key))
        if not candidates:
            break
        visited.append(min(candidates)[2])
    return visited


def connected_component(start, positions, marked, mastery_add=0, blocked=()):
    """Overload counts the complete old-conductive component, not one chain."""
    if not marked(start):
        return {start}
    blocked = {frozenset(pair) for pair in blocked}
    found, pending = {start}, [start]
    while pending:
        origin = pending.pop()
        for key, pos in positions.items():
            if (key not in found and marked(key)
                    and frozenset((origin, key)) not in blocked
                    and math.dist(positions[origin], pos) <= 4.5 + mastery_add + EPS):
                found.add(key)
                pending.append(key)
    return found


def overload_budget(spec, mechanism, nodes, natural=True):
    edges = max(0, min(nodes, spec["target_cap"]) - 1)
    eligible = nodes >= mechanism["minimum_precast_conductive_component"]
    count = spec.get("natural_overload_edges", mechanism["boosted_existing_edges"]) if natural else mechanism["boosted_existing_edges"]
    multiplier = spec.get("natural_overload_multiplier", mechanism["coefficient_multiplier"]) if natural else mechanism["coefficient_multiplier"]
    boosted = min(edges, count) if eligible else 0
    total = spec["coefficient"] + spec["edge_coefficient"] * (edges - boosted + boosted * multiplier)
    return total, edges, boosted


def actual_shield(request, missing, restoration_multiplier=1):
    return min(max(0, missing), max(0, request * restoration_multiplier))


def simulate(data, spell_id, level, geometry, horizon, cdr=0, accuracy=1,
             maintained=False, attack=100, crit_rate=.05, crit_multiplier=1.5,
             primary_scale=1, mastery_level=0, resonance=False, natural=True,
             target_survives=True, shield_missing=100, shield_drain_per_second=0,
             missing_cap=100):
    spells = {s["id"]: s for s in data["spells"]}
    spell = spells[spell_id]
    spec = spell["levels"][level - 1]
    mechanic = data["mechanics"]
    mastery = spells["L10"]["levels"][mastery_level - 1] if mastery_level else {}
    school_bonus = mastery.get("school_damage_bonus", 0) + (mechanic["resonance"]["school_damage_bonus"] if resonance else 0)
    cdr_total = cdr + (mechanic["resonance"]["school_cdr"] if resonance else 0)
    duration_add = mastery.get("conductive_duration_add", 0)
    mastery_add = mastery.get("both_conductive_range_add", 0)
    if spell_id == "L10":
        return {"casts": 0, "hit_events": 0, "damage": 0., "direct_damage": 0.,
                "derived_damage": 0., "first_hit": None, "first_release": None,
                "base_coefficient_total": 0., "restored_shield": 0., "mark_applications": 0,
                "unique_cloud_cancellations": 0, "shared_cloud_gate_blocks": 0, "ttk180_noncrit_all_hit": None,
                "school_damage_bonus": spec["school_damage_bonus"],
                "both_conductive_reach": 4.5 + spec.get("both_conductive_range_add", 0),
                "new_mark_duration_add": spec.get("conductive_duration_add", 0)}
    positions = {key: tuple(value) for key, value in geometry["positions"].items()}
    blocked = {frozenset(pair) for pair in geometry.get("blocked_pairs", [])}
    player = tuple(geometry.get("player", [0, 0]))
    queue, serial = [], 0
    marks = {key: (value["expiry"], value.get("start", 0)) for key, value in geometry.get("initial_conduction", {}).items()}
    vulnerabilities, cloud_gate = {}, {}
    totals = {"casts": 0, "hit_events": 0, "damage": 0., "direct_damage": 0.,
              "derived_damage": 0., "first_hit": None, "first_release": None,
              "base_coefficient_total": 0., "restored_shield": 0., "mark_applications": 0,
              "unique_cloud_cancellations": 0, "shared_cloud_gate_blocks": 0, "ttk180_noncrit_all_hit": None,
              "school_damage_bonus": school_bonus, "both_conductive_reach": 4.5 + mastery_add,
              "new_mark_duration_add": duration_add}
    primary_noncrit = 0
    cloud_token = 0
    shield_at, missing = 0., min(missing_cap, max(0, shield_missing))

    def push(at, kind, payload=None, priority=1):
        nonlocal serial
        serial += 1
        heapq.heappush(queue, (round(at, 10), priority, serial, kind, payload))

    def visible(a, b):
        return frozenset((a, b)) not in blocked

    def marked(key, now):
        return maintained or marks.get(key, (-1, 0))[0] > now + EPS

    def mark_age(key, now):
        if maintained:
            return now + 2
        expiry, start = marks.get(key, (-1, now))
        return now - start if expiry > now + EPS else 0

    def mark(key, now, duration):
        start = marks[key][1] if marked(key, now) and key in marks else now
        marks[key] = (now + duration + duration_add, start)
        totals["mark_applications"] += 1

    def nearest(origin, reach, require_mark=None, exclude=(), origin_key="player"):
        return sorted([key for key, pos in positions.items()
                       if key not in exclude and math.dist(origin, pos) <= reach + EPS
                       and visible(origin_key, key)
                       and (require_mark is None or marked(key, now) == require_mark)],
                      key=lambda key: (math.dist(origin, positions[key]), key))

    def damage(key, coefficient, now, derived=False, can_crit=True):
        nonlocal primary_noncrit
        if totals["first_hit"] is None:
            totals["first_hit"] = now
        totals["hit_events"] += 1
        totals["base_coefficient_total"] += coefficient
        vulnerability = vulnerabilities.get(key, (0, 0))
        vuln = vulnerability[1] if vulnerability[0] > now + EPS else 0
        scale = 1 if derived else primary_scale
        noncrit = attack * coefficient * scale * (1 + school_bonus) * (1 + vuln)
        amount = noncrit * accuracy * (crit_factor(crit_rate, crit_multiplier) if can_crit else 1)
        totals["damage"] += amount
        totals["derived_damage" if derived else "direct_damage"] += amount
        if key == "a":
            primary_noncrit += noncrit
            if primary_noncrit + EPS >= 180 and totals["ttk180_noncrit_all_hit"] is None:
                totals["ttk180_noncrit_all_hit"] = now

    # First readiness is at zero. For the passive there is no queue/cast.
    push(0, "ready", priority=2)
    now = 0
    while queue:
        now, _, _, kind, payload = heapq.heappop(queue)
        if now > horizon + EPS:
            break
        if kind in ("ready", "release") and spell_id == "L09":
            missing = min(missing_cap, missing + max(0, now - shield_at) * shield_drain_per_second)
            shield_at = now
        if kind == "ready":
            if spell_id == "L09":
                if not nearest(player, spec["enemy_range"]) or missing <= EPS:
                    if shield_drain_per_second > 0 and now < horizon:
                        push(now + .01, "ready", priority=2)
                    continue
            radius = spec.get("radius", spec.get("range", 8))
            if not nearest(player, radius if spell_id == "L06" else spec.get("range", spec.get("enemy_range", 8))):
                continue
            push(now + spell["windup"], "release", priority=2)
        elif kind == "release":
            totals["casts"] += 1
            if totals["first_release"] is None:
                totals["first_release"] = now
            push(now + effective_cd(spell["cooldowns"][level - 1], cdr_total), "ready", priority=2)
            candidates = nearest(player, spec.get("range", spec.get("enemy_range", spec.get("radius", 8))))
            if not candidates:
                continue
            main = candidates[0]
            if spell_id == "L01":
                push(now + math.dist(player, positions[main]) / spec["speed"], "simple_hit", (main, spec["coefficient"], True))
            elif spell_id == "L02":
                isolated = not any(k != main and math.dist(positions[main], pos) <= spec.get("isolated_radius", 2) + EPS for k, pos in positions.items())
                coefficient = spec["coefficient"] * (spec.get("isolated_main_multiplier", 1) if isolated else 1)
                damage(main, coefficient, now)
                mark(main, now, spec["conductive_duration"])
                direction = (positions[main][0] - player[0], positions[main][1] - player[1])
                length = math.hypot(*direction)
                direction = tuple(v / length for v in direction)
                line = []
                for key in candidates:
                    if key == main:
                        continue
                    relative = (positions[key][0] - player[0], positions[key][1] - player[1])
                    dot = sum(a * b for a, b in zip(relative, direction))
                    cross = abs(relative[0] * direction[1] - relative[1] * direction[0])
                    if 0 <= dot <= spec["range"] and cross <= spec["width"] / 2 + EPS:
                        line.append((dot, key))
                for _, key in sorted(line)[:spec["secondary_target_cap"]]:
                    damage(key, spec["secondary_coefficient"], now)
                    mark(key, now, spec["conductive_duration"])
            elif spell_id == "L03":
                # Each hop re-queries live marks. Static actors never move/die.
                push(now, "chain_hit", (main, 0, [], None))
            elif spell_id == "L04":
                damage(main, spec["coefficient"], now)
                mark(main, now, spec["conductive_duration"])
                for key in nearest(positions[main], spec["spread_range"], False, (main,), main)[:spec["neighbor_cap"]]:
                    mark(key, now, spec["conductive_duration"])
            elif spell_id == "L05":
                cloud_token += 1
                for at in spec["strike_times"]:
                    push(now + at, "cloud_strike", (cloud_token, main, set()), priority=0)
            elif spell_id == "L06":
                for key in nearest(player, spec["radius"]):
                    damage(key, spec["coefficient"], now)
                    mark(key, now, spec["conductive_duration"])
                if spec.get("followup_coefficient", 0):
                    push(now + spec["followup_delay"], "ring_followup")
            elif spell_id == "L07":
                # No elite classes here: priority is old conduction, distance, ID.
                main = min(candidates, key=lambda k: (not marked(k, now), math.dist(player, positions[k]), k))
                push(now + spec["impact_delay"], "judgment_hit", main)
            elif spell_id == "L08":
                # Declared setup finds the longest reachable component from a legal main.
                components = [(connected_component(key, positions, lambda k: marked(k, now), mastery_add, blocked), key)
                              for key in candidates if marked(key, now)]
                main = min(components, key=lambda row: (-len(row[0]), math.dist(player, positions[row[1]]), row[1]))[1] if components else candidates[0]
                members = connected_component(main, positions, lambda k: marked(k, now), mastery_add, blocked) if marked(main, now) else set()
                overload = len(members) >= mechanic["overload"]["minimum_precast_conductive_component"]
                push(now, "network_hit", (main, 0, [], members, overload, None))
            elif spell_id == "L09":
                restored = actual_shield(spec["shield_restore"], missing)
                missing -= restored
                totals["restored_shield"] += restored
                if restored > 0:
                    for key in nearest(player, spec["conductive_range"])[:spec["conductive_target_cap"]]:
                        mark(key, now, spec["conductive_duration"])
        elif kind == "simple_hit":
            key, coefficient, marks_after = payload
            if spell_id == "L01" and not marked(key, now):
                coefficient += spec.get("unconductive_coefficient_add", 0)
            damage(key, coefficient, now)
            if marks_after:
                mark(key, now, spec["conductive_duration"])
        elif kind == "chain_hit":
            key, hop, visited, old_origin_marked = payload
            if visited:
                origin = visited[-1]
                candidates = []
                for other, pos in positions.items():
                    reach = 3.5 + (1 + mastery_add if old_origin_marked and marked(other, now) else 0)
                    if other not in visited and visible(origin, other) and math.dist(positions[origin], pos) <= reach + EPS:
                        candidates.append((not marked(other, now), math.dist(positions[origin], pos), other))
                if not candidates:
                    continue
                key = min(candidates)[2]
            # Read origin's pre-hit qualification, not the mark just applied by this hit.
            origin_marked = marked(key, now)
            damage(key, spec["coefficient"] * spec["hop_decay"] ** hop, now)
            mark(key, now, spec["conductive_duration"])
            visited = visited + [key]
            if len(visited) < spec["target_cap"]:
                candidates = []
                for other, pos in positions.items():
                    reach = 3.5 + (1 + mastery_add if origin_marked and marked(other, now) else 0)
                    if other not in visited and visible(key, other) and math.dist(positions[key], pos) <= reach + EPS:
                        candidates.append((not marked(other, now), math.dist(positions[key], pos), other))
                if candidates:
                    push(now + spec["hop_interval"], "chain_hit", (min(candidates)[2], hop + 1, visited, origin_marked))
        elif kind == "cloud_strike":
            token, center, _ = payload
            if token != cloud_token:
                totals["unique_cloud_cancellations"] += 1
                continue
            # Per cast/per actor first-hit bookkeeping is kept outside payload sets.
            cast_seen = vulnerabilities.setdefault(("cloud", token), set())
            targets = nearest(positions[center], spec["radius"], origin_key=center)[:spec["strike_target_cap"]]
            for key in targets:
                if now - cloud_gate.get(key, -100) < spell["shared_strike_hit_gate"] - EPS:
                    totals["shared_cloud_gate_blocks"] += 1
                    continue
                cloud_gate[key] = now
                damage(key, spec["coefficient"], now)
                mark(key, now, spec["conductive_duration"])
                if natural and key not in cast_seen and spec.get("natural_first_hit_vulnerability", 0):
                    vulnerabilities[key] = (now + spec["vulnerability_duration"], spec["natural_first_hit_vulnerability"])
                cast_seen.add(key)
        elif kind == "ring_followup":
            for key in nearest(player, spec["radius"]):
                damage(key, spec["followup_coefficient"], now)
                if spec.get("followup_conductive_refresh", False):
                    mark(key, now, spec["conductive_duration"])
        elif kind == "judgment_hit":
            key = payload
            was_marked, age = marked(key, now), mark_age(key, now)
            damage(key, spec["coefficient"], now)
            if target_survives and was_marked:
                damage(key, spec["conductive_extra_coefficient"], now, derived=True, can_crit=False)
            if natural and target_survives and was_marked and age + EPS >= spec.get("mature_age", math.inf):
                for other in nearest(positions[key], spec.get("mature_arc_range", 0), True, (key,), key)[:spec.get("mature_arc_target_cap", 0)]:
                    damage(other, spec["mature_arc_coefficient"], now, derived=True, can_crit=False)
            if target_survives:
                mark(key, now, spec["conductive_duration"])
        elif kind == "network_hit":
            key, edge, visited, members, overloaded, old_origin_marked = payload
            if visited:
                origin = visited[-1]
                candidates = []
                for other in members - set(visited):
                    reach = 3.5 + (1 + mastery_add if old_origin_marked and marked(other, now) else 0)
                    if visible(origin, other) and math.dist(positions[origin], positions[other]) <= reach + EPS:
                        candidates.append((math.dist(positions[origin], positions[other]), other))
                if not candidates:
                    continue
                key = min(candidates)[1]
            origin_marked = marked(key, now)
            coefficient = spec["coefficient"] if edge == 0 else spec["edge_coefficient"]
            if edge:
                boost_count = spec.get("natural_overload_edges", mechanic["overload"]["boosted_existing_edges"]) if natural else mechanic["overload"]["boosted_existing_edges"]
                multiplier = spec.get("natural_overload_multiplier", mechanic["overload"]["coefficient_multiplier"]) if natural else mechanic["overload"]["coefficient_multiplier"]
                if overloaded and edge <= boost_count:
                    coefficient *= multiplier
            damage(key, coefficient, now, derived=edge > 0, can_crit=edge == 0)
            mark(key, now, spec["conductive_duration"])
            visited = visited + [key]
            if len(visited) < spec["target_cap"]:
                candidates = []
                for other in members - set(visited):
                    reach = 3.5 + (1 + mastery_add if origin_marked and marked(other, now) else 0)
                    if visible(key, other) and math.dist(positions[key], positions[other]) <= reach + EPS:
                        candidates.append((math.dist(positions[key], positions[other]), other))
                if candidates:
                    push(now + spec["edge_interval"], "network_hit", (min(candidates)[1], edge + 1, visited, members, overloaded, origin_marked))
    return totals
