"""Design-only discrete-event combat model; no imports from or writes to Godot."""
from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
import heapq
import math
import random

MODEL_VERSION = "first-run-events-1.4"
EPS = 1e-8


def choice_count(room):
    """Rewards from already CLEARED rooms only; initial choice is separate."""
    return 1 + sum(r < room for r in [1, 3] + list(range(6, 60, 3)))


def build_at(path, room):
    return dict(Counter(path["choices"][:choice_count(room)]))


def normal_stats(config, kind, room):
    info = config["normal_types"][kind]
    if room < info["introduced"]:
        raise ValueError(f"{kind} is not introduced in room {room}")
    for stage in config["normal_stages"]:
        if stage["from"] <= room <= stage["to"]:
            return stage["stats"][kind]
    raise ValueError(f"No stage for room {room}")


def combat_stats(config, build):
    player = config["player"]
    synergy = config["fire_synergy"]
    active = len(build) >= synergy["distinct_spells"]
    mastery = config["spells"]["F02"]["levels"][build["F02"]-1] if "F02" in build else {}
    # None means the attribute has no artificial cap. Probability still lies
    # in [0, 1]: >=100% always crits and never grants a second critical tier.
    crit_rate = max(0, player["crit_rate"])
    crit_cap = config["limits"].get("crit_rate")
    if crit_cap is not None:
        crit_rate = min(crit_cap, crit_rate)
    return {
        "fire": player["fire_bonus"] + mastery.get("fire_bonus", 0) + (synergy["fire_bonus"] if active else 0),
        "crit": min(1, max(0, crit_rate)),
        "crit_multiplier": player["crit_multiplier"] + mastery.get("crit_bonus", 0),
        "cdr": min(config["limits"]["cooldown_reduction"], synergy["cooldown_reduction"] if active else 0),
    }


def rounded_damage(attack, coefficient, fire_bonus, crit_multiplier=1, attack_bonus=0):
    return max(1, math.floor(attack * (1+attack_bonus) * coefficient * (1+fire_bonus) * crit_multiplier + 0.5))


def receive_damage(health, shield, damage):
    absorbed = min(shield, damage)
    return max(0, health - (damage-absorbed)), shield-absorbed


class Combat:
    """Abstract hit/coverage trials, not movement, targeting geometry, or enemy AI.

    Each spell owns its windup/CD clock. Heap insertion order breaks same-time
    ties. CD starts on successful release. Damage packets snapshot stats at
    release. Locked areas keep a fixed cohort of nearby target IDs; configured
    coverage probabilities represent position/avoidance. They are assumptions,
    not measured player accuracy. A cohort limit is a benchmark density, not an
    in-game AoE or piercing target cap.
    """

    def __init__(self, config, build, profile, enemies, seed, horizon, flags=None, incoming=None):
        self.config, self.build, self.profile = config, build, profile
        if len(build) > config["limits"]["slots"] or any(not 1 <= level <= config["limits"]["spell_level"] for level in build.values()):
            raise ValueError("Illegal slot count or spell level")
        self.rng = random.Random(seed)
        self.horizon, self.flags, self.incoming = horizon, flags or {}, incoming
        self.health = float(config["player"]["health"])
        self.shield = float(config["player"]["shield"])
        self.stat = combat_stats(config, build)
        self.targets = []
        self.boss_id = None
        for spec in enemies:
            self.add_target(spec)
        self.q, self.serial, self.time = [], 0, 0.0
        self.states = {sid: {"ready": 0.0, "casting": False} for sid in build if sid != "F02"}
        self.damage = defaultdict(float)
        self.effective = defaultdict(float)
        self.casts = Counter()
        self.extra_casts = Counter()
        self.tick_last = {}
        self.natural_count = 0
        self.book_procs = 0
        self.spirit_until = 0.0
        self.field_until = 0.0
        self.field_token = 0
        self.restored = 0.0
        self.health_damage = 0.0
        self.hurt_until = 0.0
        self.phase_started = False
        self.last_summon = None
        self.summon_groups = 0
        self.max_adds = 0
        self.first_hp_damage = None
        self.end = None
        for sid in self.states:
            self.schedule(0, "try", sid)
        if self.flags.get("fountain_interval"):
            self.schedule(self.flags["fountain_interval"], "fountain", None)
        if incoming:
            self.schedule(incoming["interval"], "incoming", None)

    def add_target(self, spec):
        target = dict(spec, id=len(self.targets), hp=float(spec["health"]), max_hp=float(spec["health"]))
        self.targets.append(target)
        if spec.get("boss"):
            self.boss_id = target["id"]
        return target["id"]

    def alive(self):
        return [t for t in self.targets if t["hp"] > EPS]

    def schedule(self, at, event, value):
        if at <= self.horizon + EPS:
            self.serial += 1
            heapq.heappush(self.q, (at, self.serial, event, value))

    def definition(self, sid):
        spec = self.config["spells"][sid]
        return spec, spec["levels"][self.build[sid]-1]

    def cooldown(self, sid):
        spec, level = self.definition(sid)
        return max(self.config["limits"]["minimum_cooldown"], level.get("cooldown", spec.get("cooldown", 0)) * (1-self.stat["cdr"]))

    def legal(self, sid):
        if not self.alive() or self.health <= EPS:
            return False
        if sid == "F10":
            return self.shield < self.config["player"]["shield"]-EPS
        if sid == "F04":
            return self.time >= self.spirit_until-EPS
        return sid != "F02"

    def target(self, highest=False):
        live = self.alive()
        if highest:
            return max(live, key=lambda t: (t["hp"], -t["id"]))["id"]
        adds = [t for t in live if t.get("add")]
        if adds and self.rng.random() < self.profile["add_priority"]:
            return adds[0]["id"]
        return live[0]["id"]

    def cohort(self, primary):
        extras = self.profile["neighbor_candidates"]
        return [primary] + [t["id"] for t in self.alive() if t["id"] != primary][:extras]

    def snapshot(self, sid):
        aura = 0.0
        if sid != "F06" and self.time < self.field_until-EPS and self.rng.random() < self.profile["aura_stay"]:
            aura = self.config["spells"]["F06"]["attack_bonus"]
        return aura

    def packet(self, delay, sid, ids, coefficient, hit, extra_hit, aura, tag=None, interval=0, token=None):
        self.schedule(self.time+delay, "damage", (sid, ids, coefficient, hit, extra_hit, aura, tag, interval, token))

    def release(self, sid, natural):
        if not self.legal(sid):
            return False
        spec, level = self.definition(sid)
        p = self.profile
        aura = self.snapshot(sid)
        if sid == "F10":
            amount = level["shield"] * (1+self.flags.get("shield_bonus", 0))
            gained = min(amount, self.config["player"]["shield"] - self.shield)
            self.shield += gained
            self.restored += gained
        elif sid == "F04":
            self.spirit_until = self.time + spec["duration"]
            count = spec["count"] + self.flags.get("spirit_extra", 0)
            i = 1
            while i * level["interval"] < spec["duration"]-EPS:
                self.schedule(self.time+i*level["interval"], "spirit", (sid, aura, count))
                i += 1
        else:
            primary = self.target(sid == "F07")
            ids = self.cohort(primary)
            coeff = level["coefficient"]
            if sid == "F01":
                self.packet(spec["travel_delay"], sid, ids, coeff, p["direct_hit"], p["bolt_extra"], aura)
                if level["secondary"]:
                    self.schedule(self.time+spec["secondary_delay"], "second_bolt", (sid, aura))
            elif sid == "F03":
                for i in range(level["drops"]):
                    self.packet(spec["impact_delay"]+i*spec["interval"], sid, ids, coeff, p["rain_hit"], p["area_extra"], aura)
                last_drop = spec["impact_delay"] + (level["drops"]-1)*spec["interval"]
                n = round(level["ground_duration"]/spec["ground_interval"])
                for i in range(1, n+1):
                    self.packet(last_drop+i*spec["ground_interval"], sid, ids, level["ground_coefficient"], p["zone_hit"], p["area_extra"], aura, "rain_ground", spec["ground_interval"])
            elif sid == "F05":
                n = round((spec["duration"]+level["end_duration"])/spec["interval"])
                for i in range(1, n+1):
                    self.packet(i*spec["interval"], sid, ids, coeff, p["zone_hit"], p["area_extra"], aura, "vortex", spec["interval"])
            elif sid == "F06":
                self.field_token += 1
                self.field_until = self.time+level["duration"]
                n = round(level["duration"]/spec["interval"])
                for i in range(1, n+1):
                    self.packet(i*spec["interval"], sid, ids, coeff, p["zone_hit"], p["area_extra"], 0, "field", spec["interval"], self.field_token)
            elif sid == "F07":
                self.schedule(self.time+spec["travel_delay"], "bomb", (sid, ids, aura, False))
                if level["aftershock"]:
                    self.schedule(self.time+spec["travel_delay"]+spec["aftershock_delay"], "bomb", (sid, ids, aura, True))
            elif sid == "F08":
                self.packet(0, sid, ids, coeff, p["direct_hit"], p["line_extra"], aura)
                if level["secondary"]:
                    self.packet(spec["secondary_delay"], sid, ids, level["secondary"], p["direct_hit"], p["line_extra"], aura)
            elif sid == "F09":
                self.packet(0, sid, ids, coeff, 1, p["area_extra"], aura)
        if natural:
            self.casts[sid] += 1
            self.natural_count += 1
            if self.flags.get("book") and self.natural_count % 3 == 0:
                self.book_procs += 1
                pool = [s for s in self.states if self.legal(s)]
                if pool:
                    self.schedule(self.time, "extra", self.rng.choice(pool))
        else:
            self.extra_casts[sid] += 1
        return True

    def damage_modifiers(self, sid, target_id):
        """Extension hook: coefficient multiplier and additive crit multiplier."""
        return 1.0, 0.0

    def after_damage(self, sid, target_id, critical, actual, aura):
        """Extension hook; no events or RNG in the base model."""

    def deal(self, sid, target_id, coefficient, aura):
        target = self.targets[target_id]
        if target["hp"] <= EPS:
            return
        critical = self.rng.random() < self.stat["crit"]
        multiplier, crit_add = self.damage_modifiers(sid, target_id)
        crit = self.stat["crit_multiplier"]+crit_add if critical else 1
        damage = rounded_damage(self.config["player"]["attack"], coefficient*multiplier, self.stat["fire"], crit, aura)
        actual = min(damage, target["hp"])
        target["hp"] -= actual
        self.damage[sid] += damage
        self.effective[sid] += actual
        if target.get("boss"):
            boss = target.get("boss")
            if boss.get("phase_fraction") and not self.phase_started and target["hp"] <= target["max_hp"]*boss["phase_fraction"]:
                self.phase_started = True
                self.schedule(self.time+boss["transition"], "summon", boss)
            if target["hp"] <= EPS:
                self.end = "clear"
        elif target.get("add") and target["hp"] <= EPS and self.last_summon is not None:
            if not any(t.get("add") for t in self.alive()):
                boss = self.targets[self.boss_id]["boss"]
                self.schedule(max(self.time, self.last_summon+boss["summon_interval"]), "summon", boss)
        if not self.alive():
            self.end = "clear"
        self.after_damage(sid, target_id, critical, actual, aura)

    def event(self, event, value):
        if event == "try":
            sid = value
            state = self.states[sid]
            if state["casting"] or self.time < state["ready"]-EPS:
                return
            if not self.legal(sid):
                if sid == "F04":
                    self.schedule(max(self.time+EPS, self.spirit_until), "try", sid)
                return
            if sid == "F09" and self.rng.random() > self.profile["wave_available"]:
                self.schedule(self.time+self.profile["wave_recheck_seconds"], "try", sid)
                return
            state["casting"] = True
            self.schedule(self.time+self.config["spells"][sid]["windup"], "release", sid)
        elif event == "release":
            sid = value
            state = self.states[sid]
            state["casting"] = False
            if self.release(sid, True):
                state["ready"] = self.time+self.cooldown(sid)
                self.schedule(state["ready"], "try", sid)
        elif event == "extra":
            self.release(value, False)
        elif event == "second_bolt":
            sid, aura = value
            if self.alive():
                spec, level = self.definition(sid)
                self.packet(spec["travel_delay"], sid, self.cohort(self.target()), level["secondary"], self.profile["direct_hit"], self.profile["bolt_extra"], aura)
        elif event == "spirit":
            sid, aura, count = value
            if self.alive():
                spec, level = self.definition(sid)
                for _ in range(count):
                    ids = self.cohort(self.target()) if level["pierce"] else [self.target()]
                    self.packet(0, sid, ids, level["coefficient"], self.profile["direct_hit"], self.profile["line_extra"], aura)
        elif event == "damage":
            sid, ids, coeff, hit, extra_hit, aura, tag, interval, token = value
            if token is not None and token != self.field_token:
                return
            for i, target_id in enumerate(ids):
                if self.rng.random() > hit*(extra_hit if i else 1):
                    continue
                if tag:
                    key = (tag, target_id)
                    if self.time-self.tick_last.get(key, -math.inf) < interval-EPS:
                        continue
                    self.tick_last[key] = self.time
                self.deal(sid, target_id, coeff, aura)
        elif event == "bomb":
            sid, ids, aura, aftershock = value
            _, level = self.definition(sid)
            for i, target_id in enumerate(ids):
                if self.rng.random() > self.profile["bomb_hit"]*(self.profile["area_extra"] if i else 1):
                    continue
                if aftershock:
                    center = i == 0 and self.rng.random() < self.profile["bomb_center"]
                    coeff = level["aftershock"] * (1 if center else 0.5)
                else:
                    center = i == 0 and self.rng.random() < self.profile["bomb_center"]
                    coeff = level["coefficient"] if center else level["outer"]
                self.deal(sid, target_id, coeff, aura)
        elif event == "fountain":
            for sid, state in self.states.items():
                if not state["casting"] and state["ready"] > self.time:
                    state["ready"] = self.time+(state["ready"]-self.time)*0.5
                    self.schedule(state["ready"], "try", sid)
            self.schedule(self.time+self.flags["fountain_interval"], "fountain", None)
        elif event == "incoming":
            if self.time >= self.hurt_until-EPS:
                old = self.health
                amount = self.incoming["damage"] if value is None else value
                self.health, self.shield = receive_damage(self.health, self.shield, amount)
                lost = old-self.health
                self.health_damage += lost
                if lost and self.first_hp_damage is None:
                    self.first_hp_damage = self.time
                self.hurt_until = self.time+self.config["player"]["hurt_invulnerability"]
                if self.health <= EPS:
                    self.end = "dead"
                elif "F10" in self.states:
                    self.schedule(self.time, "try", "F10")
            if self.incoming:
                self.schedule(self.time+self.incoming["interval"], "incoming", None)
        elif event == "summon":
            if self.boss_id is not None and self.targets[self.boss_id]["hp"] > EPS and not any(t.get("add") for t in self.alive()):
                for kind in value["adds"]:
                    stats = normal_stats(self.config, kind, value["room"])
                    self.add_target(dict(stats, kind=kind, add=True))
                self.last_summon = self.time
                self.summon_groups += 1
                self.max_adds = max(self.max_adds, sum(bool(t.get("add")) for t in self.alive()))

    def run(self):
        while self.q and not self.end:
            at, _, event, value = heapq.heappop(self.q)
            self.time = at
            self.event(event, value)
        elapsed = self.time if self.end else self.horizon
        assert 0 <= self.shield <= self.config["player"]["shield"]+EPS
        assert 0 <= self.health <= self.config["player"]["health"]+EPS
        assert self.max_adds <= 2
        assert sum(self.casts.values()) == self.natural_count
        assert self.book_procs <= self.natural_count//3
        return {
            "status": self.end or "timeout", "time": elapsed,
            "raw_damage": sum(self.damage.values()), "effective_damage": sum(self.effective.values()),
            "dps": sum(self.damage.values())/elapsed if elapsed else 0,
            "by_spell": dict(self.damage), "casts": dict(self.casts), "extra_casts": dict(self.extra_casts),
            "natural_count": self.natural_count, "book_procs": self.book_procs,
            "health": self.health, "shield": self.shield, "shield_restored": self.restored,
            "health_damage": self.health_damage, "first_hp_damage": self.first_hp_damage,
            "summon_groups": self.summon_groups, "max_adds": self.max_adds,
        }


def attrition(config, pattern, skip_shops=False, attribute_rewards=False, path=None, profile=None, durations=None, seed=0):
    """Scripted mistakes, with optional actual F10/cast clocks; never enemy AI.

    Growth/heals happen only on surviving clears. Attribute rewards at rooms
    6/12/21 are an explicit comparison, not a drop guarantee or new loot table.
    """
    health = config["player"]["health"]
    max_health = health
    shield_max = config["player"]["shield"]
    attack = config["player"]["attack"]
    elite_map = {e["room"]: e for e in config["elites"]}
    boss_map = {e["room"]: e for e in config["bosses"]}
    rows = []
    for room in range(1,61):
        shield = shield_max
        special = boss_map.get(room) or elite_map.get(room)
        if special:
            hits = pattern["boss_hits"] if room in boss_map else pattern["elite_hits"]
            amounts = list(special["attacks"].values())
        else:
            hits = pattern["normal_hits"] + bool(pattern["extra_every"] and room % pattern["extra_every"] == 0)
            amounts = [normal_stats(config, "M01", room)["damage"]]
        opening = health
        restored = 0
        if path:
            duration = durations["bosses"][str(room)] if room in boss_map else durations["elite"] if special else durations["normal"]
            # Avoid inventing multiple valid hits inside the 0.6s damage gate.
            duration = max(duration, (hits+1)*(config["player"]["hurt_invulnerability"]+0.01))
            c = deepcopy(config)
            c["player"].update(health=max_health,shield=shield_max,attack=attack)
            simulation = Combat(c,build_at(path,room),profile,[{"health":10**12}],seed+room,duration)
            simulation.health = health
            spacing = durations.get("hit_cluster_spacing")
            for i in range(hits):
                at = min(duration*0.25, duration-(hits+1)*spacing)+i*spacing if spacing else duration*(i+1)/(hits+1)
                simulation.schedule(max(0.01,at),"incoming",amounts[i % len(amounts)])
            outcome = simulation.run()
            health, shield, restored = outcome["health"], outcome["shield"], outcome["shield_restored"]
        else:
            for i in range(hits):
                health, shield = receive_damage(health, shield, amounts[i % len(amounts)])
                if health <= EPS:
                    break
        before_heal = health
        if health > EPS:
            if attribute_rewards:
                items = config["attribute_artifact_candidates"]
                if room == 6:
                    max_health += items["health_max_flat"]
                elif room == 12:
                    shield_max += items["shield_max_flat"]
                elif room == 21:
                    attack += items["attack_flat"]
            fraction = 0
            if room in config["recovery"]["boss_after"]:
                fraction = config["recovery"]["boss_fraction"]
            elif room in config["recovery"]["shop_after"] and not skip_shops:
                max_health += config["recovery"].get("shop_max_health_gain",0)
                fraction = config["recovery"]["shop_fraction"]
            health = min(max_health, health+max_health*fraction)
        rows.append({"room": room, "hits": hits, "hp_open": opening, "hp_before_heal": before_heal, "hp_close": health, "max_health":max_health, "shield_max":shield_max, "attack":attack, "shield_left": shield, "healed": health-before_heal, "shield_restored":restored})
        if health <= EPS:
            return {"status": "dead", "room": room, "health": health, "max_health":max_health, "rows": rows}
    return {"status": "clear", "room": 60, "health": health, "max_health":max_health, "rows": rows}
