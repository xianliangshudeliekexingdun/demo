"""Continuous-event design model. It is deliberately not a runtime replay.

Events use proposed parameters and synthetic target positions. Real current-core
measurements are held separately in runtime_baseline.json and baseline_summary.*.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
from dataclasses import dataclass
import heapq
import math
import random

EPS = 1e-8
MODEL_VERSION = "formal-fire-events-v2-windup-and-aim-correction"


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def line_distance(point, end):
    length_squared = end[0] ** 2 + end[1] ** 2
    if length_squared <= EPS:
        return distance(point, (0, 0))
    ratio = min(1, max(0, (point[0] * end[0] + point[1] * end[1]) / length_squared))
    return distance(point, (ratio * end[0], ratio * end[1]))


@dataclass
class Burn:
    expires: float
    next_tick: float
    token: int


class Model:
    def __init__(self, params, base, artifacts, generic, scenario, profile, spell_ids, level=3, seed=20261018, horizon=60):
        self.params = params
        self.geometry = params["geometry"]
        self.ar = float(self.geometry["actor_radius"])
        self.base = base
        self.specs = {k: deepcopy(v) for k, v in base["spells"].items() if k in params["retained_ids"]}
        self.specs.update(deepcopy(params["new_spells"]))
        for ident, patch in params["spell_overrides"].items():
            self.specs[ident].update(deepcopy(patch))
        self.item_specs = {**deepcopy(artifacts["items"]), **deepcopy(generic["items"])}
        self.item_specs.update(deepcopy(params.get("new_profession_items", {})))
        for ident, patch in params.get("profession_overrides", {}).items():
            self.item_specs[ident].update(deepcopy(patch))
        self.scenario = deepcopy(scenario)
        self.profile = deepcopy(profile)
        self.items = set(profile.get("items", []))
        self.burn_rule = deepcopy(params["burn"])
        if "P06" in self.items:
            self.burn_rule["duration"] = self.item_specs["P06"]["burn_duration"]
            self.burn_rule["maximum_future_ticks"] = self.item_specs["P06"]["maximum_future_ticks"]
        self.rng = random.Random(seed)
        self.horizon = horizon
        self.now = 0.0
        self.combat_active = True
        self.queue = []
        self.sequence = 0
        self.version = Counter()
        self.level = level
        self.ids = list(spell_ids)
        self.spells = {ident: self.spell(ident, level) for ident in spell_ids}
        self.health = [float(scenario.get("health", 1e9)) for _ in scenario["positions"]]
        self.dead_ids = set()
        self.burns: dict[int, Burn] = {}
        self.burn_token = 0
        self.next_cast = 0
        self.natural_count = 0
        self.offensive_count = 0
        self.zone_counter = 0
        self.zones = {}
        self.field_zone = None
        self.field_grace_until = 0.0
        self.last_area = {}
        self.patch_casts = set()
        self.patch_last = {}
        self.expiry_casts = set()
        self.charge_checked = set()
        self.charge = 0.0
        self.charge_ready = 0.0
        self.reignite_ready = {}
        self.shield_max = float(base["player"]["shield"])
        self.shield = self.shield_max
        self.last_damage = -math.inf
        self.hunt_stack = 0
        self.hunt_until = 0
        self.hunt_ready = 0
        self.metrics = Counter()
        self.by_source = Counter()
        self.by_spell = Counter()
        self.cast_times = defaultdict(list)
        self.locked_positions = {}
        self.windup_pending = {}
        self.trace = []
        self.failed_guards = []
        self.attack = float(base["player"]["attack"])
        if "U03" in self.items:
            self.attack += float(base["attribute_artifact_candidates"]["attack_flat"])
        self.crit_rate = float(base["player"]["crit_rate"]) + sum(float(self.item_specs[x].get("crit_rate_add", 0)) for x in self.items)
        if "B02" in self.items:
            self.crit_rate += self.item_specs["B02"]["fire_crit_rate_add"]
        self.crit_rate = float(profile.get("crit_rate_override", self.crit_rate))
        self._validate_inputs()

    def _validate_inputs(self):
        if len(self.ids) > 8 or len(set(self.ids)) != len(self.ids) or not 1 <= self.level <= 3:
            raise ValueError("Invalid slot/level fixture")
        if len(self.items) > self.params["targets_and_guardrails"]["maximum_items_in_comparison_build"]:
            raise ValueError("Comparison fixture exceeds nine treasure slots")
        if self.burn_rule["duration"] / self.burn_rule["interval"] > self.burn_rule["maximum_future_ticks"] + EPS:
            raise ValueError("Burn duration exceeds defined future tick limit")

    def spell(self, ident, level):
        data = deepcopy(self.specs[ident])
        data.update(deepcopy(data["levels"][level-1]))
        data["id"] = ident
        if ident == "F01" and "B01" in self.items:
            data["radius"] *= self.item_specs["B01"]["radius_multiplier"]
        if ident == "F03" and "B03" in self.items:
            data.update({k: self.item_specs["B03"][k] for k in ("fixed_center_drops", "first_drop_damage_multiplier")})
        if ident == "F06" and "B06" in self.items:
            data["radius"] *= self.item_specs["B06"]["radius_multiplier"]
        if ident == "F08" and "B08" in self.items:
            data["width"] *= self.item_specs["B08"]["width_multiplier"]
        if ident == "F10" and "B10" in self.items:
            data["shield"] += self.item_specs["B10"]["shield_restore_add"]
        if ident == "F11" and "B11" in self.items:
            data["spread_count"] += self.item_specs["B11"]["spread_count_add"]
        return data

    def schedule(self, at, priority, kind, payload=None):
        if at > self.horizon + EPS:
            return
        self.sequence += 1
        heapq.heappush(self.queue, (round(at, 9), priority, self.sequence, kind, payload))

    def position(self, actor, at=None):
        at = self.now if at is None else at
        x, y = self.scenario["positions"][actor]
        if self.scenario.get("motion") == "sinusoidal":
            phase = 2 * math.pi * at / self.scenario["period"] + actor * self.scenario["phase_per_actor"]
            x += self.scenario["amplitude_x"] * math.sin(phase)
            y += self.scenario["amplitude_y"] * math.sin(phase * .7)
        return (x, y)

    def alive(self, actor):
        return self.health[actor] > EPS

    def nearest(self, spec, at=None):
        radius = spec.get("radius", 0) if spec["kind"] == "wave" else spec.get("range", 0)
        choices = [a for a in range(len(self.health)) if self.alive(a) and distance(self.position(a, at), (0, 0)) <= radius + EPS]
        if not choices:
            return None
        if spec["kind"] == "bomb":
            return min(choices, key=lambda a: (-self.health[a], a))
        return min(choices, key=lambda a: (distance(self.position(a, at), (0, 0)), a))

    def total_cdr(self):
        value = self.base["fire_synergy"]["cooldown_reduction"] if len(self.ids) >= 3 else 0
        value += sum(self.item_specs[x].get("cooldown_reduction_add", 0) for x in self.items)
        return min(self.base["limits"]["cooldown_reduction"], max(value, self.profile.get("cdr_override", 0)))

    def cooldown(self, ident):
        cd = self.spells[ident].get("cooldown", 0)
        return max(self.base["limits"]["minimum_cooldown"], cd * (1-self.total_cdr())) if cd else 0

    def field_bonus(self):
        if "F06" not in self.spells:
            return 0.0
        zone = self.zones.get(self.field_zone)
        if (zone and self.now <= zone["expires"]+EPS) or self.now < self.field_grace_until-EPS:
            return self.spells["F06"]["attack_bonus"] * self.scenario.get("field_coverage", 0)
        return 0.0

    def zone_position(self, zone):
        if zone["kind"] == "vortex":
            elapsed = min(zone["travel_duration"], max(0, self.now-zone["born"]))
            return (zone["direction"][0]*zone["speed"]*elapsed, zone["direction"][1]*zone["speed"]*elapsed)
        return zone["center"]

    def vulnerability(self, actor):
        if "P03" not in self.items:
            return 0.0
        kinds = {z["id"] for z in self.zones.values() if z["id"] in ("F03", "F05", "F06") and
                 z.get("active_at", 0) <= self.now+EPS <= z["expires"]+EPS and
                 distance(self.position(actor), self.zone_position(z)) <= z["radius"]+self.ar+EPS}
        return self.item_specs["P03"]["fire_vulnerability"] if len(kinds) >= 2 else 0.0

    def generic_bonus(self):
        value = sum(self.item_specs[x].get("damage_bonus", 0) for x in self.items if x in ("GT03",))
        if "GU15" in self.items and self.now-self.last_damage >= self.item_specs["GU15"]["undamaged_seconds"]:
            value += self.item_specs["GU15"]["damage_bonus"]
        if "GU18" in self.items and self.scenario.get("motion") == "static" and self.now >= self.item_specs["GU18"]["stationary_seconds"]:
            value += self.item_specs["GU18"]["damage_bonus"]
        if "GU17" in self.items and self.now < self.hunt_until:
            value += self.hunt_stack*self.item_specs["GU17"]["damage_bonus_per_stack"]
        return value

    def amplification(self, actor, field=None):
        fire = float(self.base["player"]["fire_bonus"])
        if len(self.ids) >= 3:
            fire += self.base["fire_synergy"]["fire_bonus"]
        if "F02" in self.spells:
            fire += self.spells["F02"]["fire_bonus"]
        if "G01" in self.items:
            fire += self.item_specs["G01"]["fire_bonus_add"]
        return (1+(self.field_bonus() if field is None else field)) * (1+fire) * (1+self.generic_bonus()) * (1+self.vulnerability(actor))

    def damage(self, actor, coefficient, source, ident, critical=True, field=None, scale=1.0, crit_bonus=0):
        if not self.alive(actor):
            return 0.0, False
        iscrit = critical and (self.crit_rate >= 1 or self.rng.random() < max(0, self.crit_rate))
        multiplier = float(self.base["player"]["crit_multiplier"])
        if "F02" in self.spells:
            multiplier += self.spells["F02"].get("crit_bonus", 0)
        multiplier += sum(self.item_specs[x].get("crit_multiplier_add", 0) for x in self.items)
        multiplier += crit_bonus
        value = self.attack * coefficient * scale * self.amplification(actor, field) * (multiplier if iscrit else 1)
        return self.raw_damage(actor, value, source, ident), iscrit

    def raw_damage(self, actor, value, source, ident):
        actual = min(self.health[actor], max(0, value))
        self.health[actor] -= actual
        self.metrics["damage"] += actual
        self.by_source[source] += actual
        self.by_spell[ident] += actual
        if actual > 0:
            self.metrics["damage_events"] += 1
        if not self.alive(actor) and actor not in self.dead_ids:
            self.dead_ids.add(actor)
            self.metrics["kills"] += 1
            self.burns.pop(actor, None)
            if "GU17" in self.items and self.now+EPS >= self.hunt_ready:
                item = self.item_specs["GU17"]
                self.hunt_stack = min(item["maximum_stacks"], (self.hunt_stack if self.now < self.hunt_until else 0)+1)
                self.hunt_until = self.now+item["duration"]
                self.hunt_ready = self.now+item["shared_cooldown"]
        return actual

    def ignite(self, actor):
        if not self.combat_active or not self.alive(actor) or self.profile.get("disable_candidate_burn", False):
            return
        rule = self.burn_rule
        current = self.burns.get(actor)
        self.metrics["ignite_applications"] += 1
        if current and current.expires + EPS >= self.now:
            current.expires = self.now + rule["duration"]
            self.metrics["ignite_refreshes"] += 1
            return
        self.burn_token += 1
        burn = Burn(self.now+rule["duration"], self.now+rule["interval"], self.burn_token)
        self.burns[actor] = burn
        self.schedule(burn.next_tick, 0, "burn", (actor, burn.token))

    def future_ticks(self, actor):
        burn = self.burns.get(actor)
        if not burn:
            return 0
        # Existing due tick has priority 0, so after it next_tick is in the future.
        count = max(0, math.floor((burn.expires-burn.next_tick+EPS) / self.burn_rule["interval"])+1)
        if count > self.burn_rule["maximum_future_ticks"]:
            self.failed_guards.append("future tick limit")
        return min(self.burn_rule["maximum_future_ticks"], count)

    def detonate(self, actor, multiplier):
        if not self.alive(actor):
            return 0
        count = self.future_ticks(actor)
        self.burns.pop(actor, None)
        if count:
            self.metrics["detonations"] += 1
            self.metrics["detonated_future_ticks"] += count
            field = None if self.burn_rule["dynamic_field_bonus_applies"] else 0
            self.damage(actor, count*self.burn_rule["tick_coefficient"]*multiplier, "detonation", "shared_burn", critical=False, field=field)
        return count

    def spread(self, actor, spec):
        blocked = {tuple(pair) for pair in self.scenario.get("blocked_spread_pairs", [])}
        choices = [a for a in range(len(self.health)) if a != actor and self.alive(a) and a not in self.burns and
                   (actor, a) not in blocked and (a, actor) not in blocked and
                   distance(self.position(actor), self.position(a)) <= spec["spread_radius"]+EPS]
        choices.sort(key=lambda a: (distance(self.position(actor), self.position(a)), a))
        for other in choices[:spec["spread_count"]]:
            self.ignite(other)
            self.metrics["propagated_targets"] += 1

    def shield_restore(self, amount):
        if "GT01" in self.items:
            amount *= self.item_specs["GT01"]["shield_restore_multiplier"]
        actual = min(max(0, self.shield_max-self.shield), amount)
        self.shield += actual
        self.metrics["shield_restored"] += actual
        self.metrics["shield_wasted"] += amount-actual
        if "GT01" in self.items:
            self.charge = min(self.attack*self.item_specs["GT01"]["charge_attack_cap_multiplier"], self.charge+actual*self.item_specs["GT01"]["charge_per_restored_shield"])

    def post_hit(self, actor, coefficient, context, ignite=False, detonate=False, crit_bonus=0):
        ident = context["id"]
        amount, critical = self.damage(actor, coefficient, "direct" if ident.startswith("F") else "profession_proc", ident,
                                      field=context.get("field"), scale=context.get("scale", 1), crit_bonus=crit_bonus)
        if amount <= 0:
            return
        cast = context["cast"]
        natural = context["natural"]
        if "GT01" in self.items and natural and cast not in self.charge_checked:
            self.charge_checked.add(cast)
            if self.charge > 0 and self.now+EPS >= self.charge_ready and self.alive(actor):
                self.raw_damage(actor, self.charge, "fixed_charge", "GT01")
                self.charge = 0
                self.charge_ready = self.now+self.item_specs["GT01"]["shared_cooldown"]
                self.metrics["charge_releases"] += 1
        if "P02" in self.items and natural and critical and ident in ("F01", "F03", "F07", "F08", "F09", "F11") and context.get("component") != "area" and cast not in self.patch_casts:
            self.patch_casts.add(cast)
            item = self.item_specs["P02"]
            center = self.position(actor)
            for tick in range(1, round(item["duration"]/item["interval"])+1):
                self.schedule(self.now+tick*item["interval"], 7, "patch", (center, cast))
        if not self.alive(actor):
            return
        if detonate:
            multiplier = self.burn_rule["detonation_multiplier_by_F07_level"][self.level-1]
            if "G04" in self.items and natural:
                multiplier += self.item_specs["G04"]["detonation_multiplier_add"]
            count = self.detonate(actor, multiplier)
            if count and self.alive(actor) and "G04" in self.items and natural and self.now+EPS >= self.reignite_ready.get(actor, -math.inf):
                item = self.item_specs["G04"]
                self.reignite_ready[actor] = self.now+item["per_actor_cooldown"]
                self.schedule(self.now+item["reignite_delay"], 12, "reignite", actor)
                self.metrics["reignites_scheduled"] += 1
        if ignite:
            self.ignite(actor)

    def cast(self, ident, natural=True, scale=1):
        if not self.combat_active:
            return False
        spec = self.spells[ident]
        if spec["kind"] == "shield":
            if self.shield >= self.shield_max-EPS or not any(self.alive(a) for a in range(len(self.health))):
                return False
            target = None
        else:
            target = self.nearest(spec)
            if target is None:
                return False
        self.next_cast += 1
        cast = self.next_cast
        context = {"id": ident, "cast": cast, "natural": natural, "scale": scale, "field": self.field_bonus()}
        self.metrics["natural_casts" if natural else "extra_casts"] += 1
        self.cast_times[ident].append(self.now)
        kind = spec["kind"]
        if kind == "shield":
            self.shield_restore(spec["shield"])
        elif kind in ("bolt", "beam", "wave", "brand", "bomb"):
            center = self.position(target)
            if kind == "bomb" and natural:
                center = self.locked_positions.get(ident, self.position(target, self.now-spec.get("windup", 0)))
            payload = (ident, context, target, center, False)
            self.schedule(self.now+spec.get("travel_delay", 0), 10, "impact", payload)
            if spec.get("secondary", 0) > 0:
                if kind == "bolt":
                    self.schedule(self.now+spec["secondary_delay"], 10, "secondary_bolt", (ident, context))
                else:
                    self.schedule(self.now+spec["secondary_delay"], 10, "impact", (ident, context, target, center, True))
        elif kind == "rain":
            center = self.position(target)
            end = spec["impact_delay"]+(spec["drops"]-1)*spec["interval"]
            self.make_zone(ident, context, center, 0, end, 0, spec["radius"], kind="rain", active_delay=spec["impact_delay"])
            for tick in range(spec["drops"]):
                angle = self.rng.random()*2*math.pi
                radius = math.sqrt(self.rng.random())*spec["radius"]*self.geometry["rain_scatter_fraction"]
                pos = (center[0]+math.cos(angle)*radius, center[1]+math.sin(angle)*radius)
                coefficient = spec["coefficient"]
                if tick == 0:
                    coefficient = spec.get("first_drop_coefficient", coefficient)
                if tick < spec.get("fixed_center_drops", 0):
                    pos = center
                    if tick == 0:
                        coefficient *= spec.get("first_drop_damage_multiplier", 1)
                self.schedule(self.now+spec["impact_delay"]+tick*spec["interval"], 10, "rain", (ident, context, pos, coefficient, tick == spec["drops"]-1, center))
        elif kind == "vortex":
            center = self.position(target)
            length = distance(center, (0, 0))
            direction = (center[0]/length, center[1]/length) if length > EPS else (0, 1)
            self.make_zone(ident, context, (0, 0), spec["coefficient"], spec["duration"]+spec["end_duration"], spec["interval"], spec["radius"],
                           kind="vortex", direction=direction, speed=spec["speed"], travel_duration=spec["duration"])
        elif kind == "field":
            if self.field_zone:
                self.zones.pop(self.field_zone, None)
            self.field_grace_until = 0.0
            ctx = {**context, "field": 0}
            self.field_zone = self.make_zone(ident, ctx, (0, 0), spec["coefficient"], spec["duration"], spec["interval"], spec["radius"], kind="field")
        if natural:
            self.natural_count += 1
            offensive = kind not in ("shield", "passive")
            if offensive:
                self.offensive_count += 1
            if "P04" in self.items and self.natural_count % self.item_specs["P04"]["natural_casts_per_extra"] == 0:
                choices = [x for x in self.ids if self.spells[x]["kind"] != "passive" and
                           ((self.spells[x]["kind"] == "shield" and self.shield < self.shield_max-EPS) or self.nearest(self.spells[x]) is not None)]
                if choices:
                    self.cast(self.rng.choice(choices), False, self.item_specs["P04"]["damage_multiplier"])
            if "G01" in self.items and offensive and self.offensive_count % self.item_specs["G01"]["offensive_casts_per_echo"] == 0:
                self.cast(ident, False, self.item_specs["G01"]["echo_damage_multiplier"])
        return True

    def make_zone(self, ident, context, center, coefficient, duration, interval, radius, **extra):
        self.zone_counter += 1
        key = self.zone_counter
        zone = {"key": key, "id": ident, "context": context, "center": center, "coefficient": coefficient,
                "born": self.now, "expires": self.now+duration, "interval": interval, "radius": radius,
                "first_hits": set(), "active_at": self.now+extra.pop("active_delay", 0), **extra}
        self.zones[key] = zone
        if "G03" in self.items and extra.get("kind") != "rain" and context["natural"] and self.profile.get("g03_trigger", "age_two_seconds") == "age_two_seconds":
            self.schedule(self.now+self.item_specs["G03"]["minimum_area_age"], 9, "g03_age", key)
        if interval:
            for tick in range(1, math.floor((duration+EPS)/interval)+1):
                self.schedule(self.now+tick*interval, 6, "zone", key)
        self.schedule(self.now+duration, 30, "expire", key)
        return key

    def impact(self, payload):
        ident, context, target, center, secondary = payload
        spec = self.spells[ident]
        kind = spec["kind"]
        actors = [a for a in range(len(self.health)) if self.alive(a)]
        if kind == "bolt":
            # A sample-at-landing approximation; crossing collisions are intentionally omitted.
            if not self.alive(target) or distance(self.position(target), center) > self.ar+self.geometry["bolt_collision_radius"]+EPS:
                return
            actors = [a for a in actors if distance(self.position(a), center) <= spec["radius"]+self.ar+EPS]
        elif kind == "beam":
            length = distance(center, (0, 0))
            end = (center[0]*spec["range"]/length, center[1]*spec["range"]/length) if length > EPS else center
            actors = [a for a in actors if line_distance(self.position(a), end) <= spec["width"]/2+self.ar+EPS]
        elif kind == "wave":
            actors = [a for a in actors if distance(self.position(a), (0, 0)) <= spec["radius"]+self.ar+EPS]
        elif kind == "brand":
            actors = [target] if self.alive(target) else []
        elif kind == "bomb":
            actors = [a for a in actors if distance(self.position(a), center) <= spec["radius"]+self.ar+EPS]
        for actor in actors:
            before = self.health[actor]
            coefficient = spec["secondary"] if secondary else spec["coefficient"]
            bonus = 0
            if kind == "bomb":
                inside = distance(self.position(actor), center) <= spec["center_radius"]+self.ar+EPS
                coefficient = spec["coefficient"] if inside else spec["outer"]
                if inside and "B07" in self.items:
                    coefficient *= self.item_specs["B07"]["main_center_damage_multiplier"]
                    bonus = self.item_specs["B07"]["main_center_crit_multiplier_add"]
            ignite = kind in ("bolt", "wave", "brand") or (kind == "beam" and not secondary)
            self.post_hit(actor, coefficient, context, ignite=ignite, detonate=kind == "bomb", crit_bonus=bonus)
            if kind == "brand" and self.health[actor] < before:
                self.spread(actor, spec)
        if kind == "bomb" and spec.get("aftershock", 0):
            self.schedule(self.now+spec["aftershock_delay"], 10, "aftershock", (ident, context, center))

    def run(self):
        for ident in self.ids:
            if self.spells[ident]["kind"] != "passive":
                self.version[ident] += 1
                self.schedule(0, 19, "cast_begin", (ident, self.version[ident]))
        if "P05" in self.items:
            self.schedule(self.item_specs["P05"]["interval"], 3, "spring")
        if "GU11" in self.items:
            self.schedule(self.item_specs["GU11"]["interval"], 4, "shield_regen")
        if self.profile.get("shield_loss_feed"):
            self.schedule(self.profile["shield_loss_feed"]["interval"], 2, "shield_loss")
        self.cooldown_ready = {x: 0.0 for x in self.ids}
        while self.queue:
            self.now, _, _, kind, payload = heapq.heappop(self.queue)
            self.metrics["events_processed"] += 1
            if self.metrics["events_processed"] > 1000000:
                raise RuntimeError("event termination guard")
            self.dispatch(kind, payload)
        self.now = self.horizon
        return {"damage": self.metrics["damage"], "dps": self.metrics["damage"] / self.horizon,
                "by_source": dict(self.by_source), "by_spell": dict(self.by_spell), "metrics": dict(self.metrics),
                "casts_at": dict(self.cast_times), "burns_remaining": len(self.burns), "charge_remaining": self.charge,
                "failed_guards": self.failed_guards}

    def dispatch(self, kind, payload):
        if not self.combat_active:
            return
        if kind == "cast_begin":
            ident, token = payload
            if token != self.version[ident]:
                return
            spec = self.spells[ident]
            target = self.nearest(spec) if spec["kind"] != "shield" else None
            legal = target is not None if spec["kind"] != "shield" else self.shield < self.shield_max-EPS and any(self.alive(a) for a in range(len(self.health)))
            if legal:
                if spec["kind"] == "bomb":
                    self.locked_positions[ident] = self.position(target)
                self.windup_pending[ident] = True
                self.schedule(self.now+spec.get("windup", 0), 20, "cast", (ident, token))
            else:
                self.schedule(self.now+self.params["timing"]["no_target_retry"], 19, "cast_begin", (ident, token))
        elif kind == "cast":
            ident, token = payload
            if token != self.version[ident]:
                return
            success = self.cast(ident)
            self.windup_pending[ident] = False
            self.cooldown_ready[ident] = self.now+self.cooldown(ident) if success else self.now
            delay = self.cooldown(ident) if success else self.params["timing"]["no_target_retry"]
            self.schedule(self.now+delay, 19, "cast_begin", (ident, token))
        elif kind == "impact":
            self.impact(payload)
        elif kind == "secondary_bolt":
            ident, context = payload
            target = self.nearest(self.spells[ident])
            if target is not None:
                self.schedule(self.now+self.spells[ident]["travel_delay"], 10, "impact", (ident, context, target, self.position(target), True))
        elif kind == "burn":
            actor, token = payload
            burn = self.burns.get(actor)
            if not burn or burn.token != token or not self.alive(actor):
                return
            if self.now > burn.expires+EPS:
                self.burns.pop(actor, None)
                return
            field = None if self.burn_rule["dynamic_field_bonus_applies"] else 0
            self.damage(actor, self.burn_rule["tick_coefficient"], "burn", "shared_burn", critical=False, field=field)
            self.metrics["burn_ticks"] += 1
            if actor in self.burns:
                burn.next_tick = self.now+self.burn_rule["interval"]
                self.schedule(burn.next_tick, 0, "burn", (actor, token))
                self.schedule(burn.expires, 40, "burn_expire", (actor, token))
        elif kind == "burn_expire":
            actor, token = payload
            burn = self.burns.get(actor)
            if burn and burn.token == token and self.now+EPS >= burn.expires:
                self.burns.pop(actor, None)
        elif kind == "rain":
            ident, context, center, coefficient, last, rain_center = payload
            self.metrics["rain_drops"] += 1
            for actor in range(len(self.health)):
                if self.alive(actor) and distance(self.position(actor), center) <= self.geometry["rain_impact_radius"]+self.ar+EPS:
                    self.metrics["rain_actor_hits"] += 1
                    self.post_hit(actor, coefficient, context, ignite=True)
            if last and self.spells[ident].get("ground_duration", 0):
                spec = self.spells[ident]
                self.make_zone(ident, context, rain_center, spec["ground_coefficient"], spec["ground_duration"], spec["ground_interval"], spec["radius"], kind="rain_ground")
        elif kind == "zone":
            zone = self.zones.get(payload)
            if not zone:
                return
            for actor in range(len(self.health)):
                if not self.alive(actor) or distance(self.position(actor), self.zone_position(zone)) > zone["radius"]+self.ar+EPS:
                    continue
                key = (zone["id"], actor)
                if self.now-self.last_area.get(key, -math.inf) < zone["interval"]-EPS:
                    continue
                # All same-time eligible zones choose the highest coefficient.
                peers = [z for z in self.zones.values() if z["id"] == zone["id"] and z["interval"] and
                         z["born"]+z["interval"]-EPS <= self.now <= z["expires"]+EPS and
                         abs((self.now-z["born"])/z["interval"]-round((self.now-z["born"])/z["interval"])) < EPS and
                         distance(self.position(actor), self.zone_position(z)) <= z["radius"]+self.ar+EPS]
                winner = max(peers, key=lambda z: (z["coefficient"], -z["key"])) if peers else zone
                if winner["key"] != payload:
                    continue
                self.last_area[key] = self.now
                first = actor not in zone["first_hits"]
                zone["first_hits"].add(actor)
                ctx = {**zone["context"], "component": "area"}
                self.post_hit(actor, zone["coefficient"], ctx, ignite=first and zone["kind"] in ("field", "vortex"))
        elif kind == "expire":
            zone = self.zones.pop(payload, None)
            if zone and zone["kind"] == "field":
                self.field_grace_until = self.now+self.spells["F06"].get("grace", 0)*self.scenario.get("field_coverage", 0)
            if zone and self.profile.get("g03_trigger", "age_two_seconds") == "expiration":
                self.g03_burst(zone)
        elif kind == "g03_age":
            zone = self.zones.get(payload)
            if zone:
                self.g03_burst(zone)
        elif kind == "reignite":
            if self.alive(payload):
                self.ignite(payload)
                self.metrics["reignites_applied"] += 1
        elif kind == "aftershock":
            ident, context, center = payload
            spec = self.spells[ident]
            for actor in range(len(self.health)):
                if self.alive(actor) and distance(self.position(actor), center) <= spec["radius"]+self.ar+EPS:
                    self.post_hit(actor, spec["aftershock"], context)
        elif kind == "patch":
            center, cast = payload
            item = self.item_specs["P02"]
            for actor in range(len(self.health)):
                if self.alive(actor) and distance(self.position(actor), center) <= item["radius"]+self.ar+EPS and self.now-self.patch_last.get(actor, -math.inf) >= item["interval"]-EPS:
                    self.patch_last[actor] = self.now
                    self.damage(actor, item["coefficient"], "profession_proc", "P02", field=0)
        elif kind == "spring":
            for ident in self.ids:
                if self.spells[ident]["kind"] != "passive" and self.cooldown_ready[ident] > self.now+EPS:
                    self.cooldown_ready[ident] = self.now+(self.cooldown_ready[ident]-self.now)*self.item_specs["P05"]["remaining_cooldown_multiplier"]
                    self.version[ident] += 1
                    self.schedule(self.cooldown_ready[ident], 19, "cast_begin", (ident, self.version[ident]))
            self.schedule(self.now+self.item_specs["P05"]["interval"], 3, "spring")
        elif kind == "shield_regen":
            self.shield_restore(self.item_specs["GU11"]["shield_restore"])
            self.schedule(self.now+self.item_specs["GU11"]["interval"], 4, "shield_regen")
        elif kind == "shield_loss":
            feed = self.profile["shield_loss_feed"]
            loss = min(self.shield, feed["amount"])
            self.shield -= loss
            self.metrics["synthetic_shield_loss"] += loss
            if loss:
                self.last_damage = self.now
            self.schedule(self.now+feed["interval"], 2, "shield_loss")

    def g03_burst(self, zone):
        if zone["kind"] == "rain" or "G03" not in self.items or not zone["context"]["natural"] or zone["context"]["cast"] in self.expiry_casts:
            return
        self.expiry_casts.add(zone["context"]["cast"])
        self.metrics["g03_bursts"] += 1
        item = self.item_specs["G03"]
        for actor in range(len(self.health)):
            if self.alive(actor) and distance(self.position(actor), self.zone_position(zone)) <= item["radius"]+self.ar+EPS:
                self.damage(actor, item["coefficient"], "profession_proc", "G03", field=0)

    def stop_combat(self):
        """Design boundary: end this synthetic combat, with no delayed catch-up."""
        self.combat_active = False
        self.queue.clear()
        self.burns.clear()
        self.zones.clear()
