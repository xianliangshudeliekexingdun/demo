"""Isolated layout, spawn and spike model. No Godot or live campaign state.

Navigation uses axis-expanded AABBs and four-neighbour paths. Square expansion
is conservative at corners relative to circular actors; no diagonal shortcuts.
All tuning is supplied by callers, never loaded as runtime defaults here.
"""
from collections import deque
from math import hypot


def box(center, size):
    w, d = (size, size) if isinstance(size, (float, int)) else size
    return (center[0] - w / 2, center[1] - d / 2,
            center[0] + w / 2, center[1] + d / 2)


def blocked(point, rect, padding):
    x, z = point
    return (rect[0] - padding <= x <= rect[2] + padding and
            rect[1] - padding <= z <= rect[3] + padding)


def free(point, width, depth, rects, radius, margin):
    p = radius + margin
    return (abs(point[0]) <= width / 2 - p + 1e-9 and
            abs(point[1]) <= depth / 2 - p + 1e-9 and
            not any(blocked(point, r, p) for r in rects))


class Grid:
    def __init__(self, width, depth, rects, radius, margin, step):
        self.step = step
        self.nodes = {(i, j) for i in range(round(-width / 2 / step), round(width / 2 / step) + 1)
                      for j in range(round(-depth / 2 / step), round(depth / 2 / step) + 1)
                      if free((i * step, j * step), width, depth, rects, radius, margin)}

    def world(self, node):
        return tuple(round(v * self.step, 9) for v in node)

    def nearest(self, point):
        return min(self.nodes, key=lambda n: (hypot(n[0] * self.step - point[0],
                                                   n[1] * self.step - point[1]), n))

    def distances(self, starts, allowed=None):
        allowed = self.nodes if allowed is None else allowed
        d = {n: 0 for n in starts if n in allowed}
        q = deque(d)
        while q:
            x, z = q.popleft()
            for n in ((x - 1, z), (x + 1, z), (x, z - 1), (x, z + 1)):
                if n in allowed and n not in d:
                    d[n] = d[(x, z)] + 1
                    q.append(n)
        return d

    def safe_nodes(self, hazard_rects, radius, margin):
        return {n for n in self.nodes
                if not any(blocked(self.world(n), r, radius + margin) for r in hazard_rects)}

    def escape_distance(self, hazard_rects, radius, margin):
        safe = self.safe_nodes(hazard_rects, radius, margin)
        d = self.distances(safe)
        assert len(d) == len(self.nodes), "An occupied hazard has no static escape path"
        return max(d.values(), default=0) * self.step


def spawn_slots(spawn):
    return [(x, round(z + offset, 6)) for x in spawn["side_x"]
            for z in spawn["anchor_z"] for offset in spawn["slot_offsets_z"]]


def eligible_slots(slots, player, existing, rects, hazards, width, depth,
                   spawn, safe_distance):
    radius, margin = spawn["normal_footprint_radius"], spawn["static_clearance"]
    return [p for p in slots
            if free(p, width, depth, rects + hazards, radius, margin)
            and hypot(p[0] - player[0], p[1] - player[1]) >= safe_distance - 1e-9
            and all(hypot(p[0] - e[0], p[1] - e[1]) >=
                    radius + e[2] + spawn["existing_enemy_clearance"] - 1e-9 for e in existing)]


def reserve_batch(slots, player, existing, rects, hazards, width, depth,
                  spawn, ordinary_spawn, batch_size, cap, rng):
    if (len(existing) > ordinary_spawn["next_batch_when_alive_at_most"] or
            len(existing) + batch_size > cap):
        return None
    eligible = eligible_slots(slots, player, existing, rects, hazards, width, depth,
                              spawn, ordinary_spawn["safe_player_distance"])
    # Slot spacing is a source invariant. Once filtered, any subset is valid;
    # alternate sides when possible, without a greedy geometric dead end.
    if len(eligible) < batch_size:
        return None
    sides = [[p for p in eligible if p[0] < 0], [p for p in eligible if p[0] >= 0]]
    for side in sides:
        rng.shuffle(side)
    first = rng.randrange(2)
    picked = []
    while len(picked) < batch_size:
        side = (first + len(picked)) % 2
        if not sides[side]:
            side = 1 - side
        picked.append(sides[side].pop())
    return picked


def valid_reservation(picked, player, existing, rects, hazards, width, depth,
                      spawn, ordinary_spawn, cap):
    if not picked or len(existing) > ordinary_spawn["next_batch_when_alive_at_most"]:
        return False
    if len(picked) + len(existing) > cap:
        return False
    allowed = set(eligible_slots(picked, player, existing, rects, hazards, width,
                                 depth, spawn, ordinary_spawn["safe_player_distance"]))
    return len(set(picked)) == len(picked) and len(allowed) == len(picked)


def spike_clock(spikes, groups, heavy_requests, gap, horizon):
    """Single shared clock: no overlapping heavy jobs and spike windows.

    Heavy durations are test fixtures. Due spikes win ties; a running job is
    never interrupted, and the next rest begins at actual retraction.
    """
    requests = sorted([dict(r, index=i) for i, r in enumerate(heavy_requests)],
                      key=lambda r: (r["ready"], r["index"]))
    due, previous_end, previous_kind, activation = spikes["first_warning_after_room_start"], 0, None, 0
    events = []
    while groups or requests:
        candidates = []
        if groups:
            start = max(due, previous_end + (gap if previous_kind == "heavy" else 0))
            candidates.append((start, 0, "spike"))
        if requests:
            candidates.append((max(requests[0]["ready"], previous_end +
                                   (gap if previous_kind else 0)), 1, "heavy"))
        start, _, kind = min(candidates)
        if start >= horizon:
            break
        if kind == "spike":
            end = start + spikes["warning"] + spikes["active"]
            events.append({"kind": kind, "start": start, "active_start": start + spikes["warning"],
                           "end": end, "group": groups[activation % len(groups)], "activation": activation})
            activation += 1
            due = end + spikes["rest_after_retract"]
        else:
            request = requests.pop(0)
            end = start + request["duration"]
            events.append({"kind": kind, "start": start, "end": end, "request": request})
        previous_end, previous_kind = end, kind
    return events


def spike_contacts(activation, contacts, damage, health, shield, hurt_until,
                   invulnerability, stop_time=float("inf")):
    """Contacts belong to one group activation, including leave/re-enter.

    First active contact consumes the sole attempt even when invulnerable.
    Retraction and stop_time are exclusive boundaries. Shield absorbs first.
    """
    for t in sorted(contacts):
        if t >= stop_time or health <= 0:
            break
        if activation["active_start"] <= t < activation["end"]:
            if t < hurt_until:
                return health, shield, hurt_until, 0
            taken = max(0, damage - shield)
            return max(0, health - taken), max(0, shield - damage), t + invulnerability, damage
    return health, shield, hurt_until, 0
