"""Design-only event budgets. No Godot runtime or AI is emulated here."""
from __future__ import annotations

import heapq
import math

MODEL_VERSION = "five-schools-design-1.1"
EPS = 1e-9


def effective_cd(base: float, reduction: float, cap: float = 0.6, minimum: float = 0.2) -> float:
    return max(minimum, base * (1.0 - min(max(reduction, 0.0), cap)))


def crit_expectation(rate: float, multiplier: float) -> float:
    return 1.0 + min(max(rate, 0.0), 1.0) * (multiplier - 1.0)


def aim_center_reachable(target_distance, actual_path_limit, side_offset=0.0):
    """Conservative center-reach guard; does not simulate collider edge overlaps."""
    return math.hypot(target_distance, side_offset) <= actual_path_limit + EPS


def spell_events(spell: dict, probe: dict, level: int, horizon: float, reduction: float, targets: int):
    """Return exact hit opportunities under the probe's explicit geometric assumptions."""
    index = level - 1
    windup = float(spell["windup"])
    cd = effective_cd(float(spell["cooldowns"][index]), reduction)
    events: list[tuple[float, float, int]] = []
    casts = 0
    if probe["mode"] == "casts":
        release = windup
        while release <= horizon + EPS:
            casts += 1
            for hit in probe["events"]:
                if targets < int(hit.get("minimum_targets", [1, 1, 1])[index]):
                    continue
                at = release + float(hit["delay"][index])
                if at <= horizon + EPS:
                    count = min(max(0, targets - int(hit.get("excluded_targets", 0))), int(hit["target_caps"][index]))
                    if count:
                        events.append((at, float(hit["coefficients"][index]), count))
            release += windup + cd
        return sorted(events), casts, {"max_alive": 0, "summons": 0}
    if probe["mode"] != "summon":
        raise ValueError(f"Unsupported probe mode: {probe['mode']}")

    capacity = int(probe["capacity"][index])
    duration = float(probe["duration"][index])
    interval = float(probe["attack_interval"][index])
    delay = float(probe["attack_delay"][index])
    coefficient = float(probe["attack_coefficient"][index])
    target_cap = int(probe["target_caps"][index])
    per_cast = int(probe["summon_per_cast"][index])
    # Same timestamp: old attacks -> expiry -> readiness -> completed release.
    queue = [(0.0, 2, 0, "ready", -1)]
    serial = 1
    units: dict[int, float] = {}
    next_id = 0
    ready_at = 0.0
    casting = False
    max_alive = summons = 0

    def push(at, priority, kind, unit=-1):
        nonlocal serial
        heapq.heappush(queue, (at, priority, serial, kind, unit))
        serial += 1

    while queue:
        at, _, _, kind, unit = heapq.heappop(queue)
        if at > horizon + EPS:
            break
        if kind == "attack":
            if unit in units and at <= units[unit] + EPS:
                events.append((at, coefficient, min(targets, target_cap)))
                if at + interval <= units[unit] + EPS:
                    push(at + interval, 0, "attack", unit)
        elif kind == "expire":
            units.pop(unit, None)
            push(max(at, ready_at), 2, "ready")
        elif kind == "ready":
            if not casting and at + EPS >= ready_at and len(units) < capacity:
                casting = True
                push(at + windup, 3, "release")
        elif kind == "release":
            casting = False
            free = capacity - len(units)
            if free <= 0:
                continue
            casts += 1
            ready_at = at + cd
            for _ in range(min(free, per_cast)):
                next_id += 1
                units[next_id] = at + duration
                summons += 1
                push(at + delay, 0, "attack", next_id)
                push(at + duration, 1, "expire", next_id)
            max_alive = max(max_alive, len(units))
            push(ready_at, 2, "ready")
    return sorted(events), casts, {"max_alive": max_alive, "summons": summons}


def evaluate(spell: dict, probe: dict, level: int, horizon: float, reduction: float, targets: int,
             accuracy: float, attack: float = 100.0, crit_rate: float = 0.05,
             crit_multiplier: float = 1.5, target_health: float = 180.0) -> dict:
    events, casts, units = spell_events(spell, probe, level, horizon, reduction, targets)
    total_coefficient = sum(c * n for _, c, n in events)
    direct = attack * total_coefficient
    expected = direct * accuracy * crit_expectation(crit_rate, crit_multiplier)
    primary_damage = 0.0
    ttk = None
    if accuracy == 1.0:
        isolated, _, _ = spell_events(spell, probe, level, horizon, reduction, 1)
        for at, coefficient, _ in isolated:
            primary_damage += attack * coefficient
            if primary_damage + EPS >= target_health:
                ttk = at
                break
    return {
        "spell_id": spell["id"], "level": level, "horizon": horizon,
        "cdr": reduction, "targets": targets, "accuracy_expectation": accuracy,
        "casts": casts, "hit_opportunities": len(events),
        "first_hit": events[0][0] if events else None,
        "base_coefficient_total": total_coefficient,
        "noncritical_all_hit_damage": direct,
        "expected_damage": expected, "expected_dps": expected / horizon,
        "ttk180_isolated_noncritical_all_hit": ttk,
        **units,
    }


def ordered_chain(start: str, positions: dict[str, tuple[float, float]], maximum_targets: int,
                  reach: float, blocked: set[frozenset] | None = None) -> list[str]:
    """A single no-revisit path; each edge checks distance and LOS."""
    blocked = blocked or set()
    visited = [start]
    while len(visited) < maximum_targets:
        current = visited[-1]
        candidates = [key for key in positions if key not in visited
                      and math.dist(positions[current], positions[key]) <= reach + EPS
                      and frozenset((current, key)) not in blocked]
        if not candidates:
            break
        visited.append(min(candidates, key=lambda key: (math.dist(positions[current], positions[key]), key)))
    return visited


def coefficient_buckets(attack, coefficient, scale=1.0, common=(), school=(), vulnerability=()):
    return attack * coefficient * scale * (1 + sum(common)) * (1 + sum(school)) * (1 + sum(vulnerability))


def construction_remove(objects: dict, identity: int, reason: str, damage_reasons: set[str]):
    """One terminal transition, so expiry/consume/replacement cannot all pay out."""
    item = objects.pop(identity, None)
    return item is not None and reason in damage_reasons


def track_path(points: list[tuple[float, float]], teleported: set[int] | None = None):
    """Input is resolved combat positions; teleports/room changes are excluded."""
    teleported = teleported or set()
    return sum(math.dist(a, b) for i, (a, b) in enumerate(zip(points, points[1:]), start=1) if i not in teleported)
