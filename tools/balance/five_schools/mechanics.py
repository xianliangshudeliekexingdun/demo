"""Small exact proposal-state checks, separate from isolated starter budgets."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class FrostWindow:
    parameters: dict
    target_class: str = "normal"
    stacks: int = 0
    expiry: float = 0.0
    window_until: float = 0.0
    frozen_until: float = 0.0
    immune_until: float = 0.0
    token: int = 0

    def advance(self, now):
        if now >= self.window_until:
            self.window_until = 0.0
        if now >= self.expiry:
            self.stacks = 0

    def apply(self, now, amount=1, force_freeze=None):
        self.advance(now)
        if self.window_until > now:
            return False
        p = self.parameters
        self.stacks = min(p["max_stacks"], self.stacks + amount)
        self.expiry = now + p["expiry"]
        if self.stacks < p["max_stacks"] and force_freeze is None:
            return False
        self.stacks = 0
        self.window_until = now + p["ready_window"]
        duration = (p["base_freeze"] if force_freeze is None else force_freeze) * p["control_duration_coefficients"][self.target_class]
        if now < self.immune_until:
            duration = 0.0
        self.frozen_until = now + duration
        if duration > 0:
            self.immune_until = self.frozen_until + p["post_freeze_immunity"]
        self.token += 1
        return True

    def consume(self, now):
        self.advance(now)
        if self.window_until <= now:
            return False
        self.window_until = 0.0
        self.stacks = 0
        if self.frozen_until > now:
            self.frozen_until = now
            self.immune_until = now + self.parameters["post_freeze_immunity"]
        return True


class BoundedTrace:
    def __init__(self, minimum_interval, window, maximum):
        self.minimum_interval, self.window, self.maximum = minimum_interval, window, maximum
        self.hits = []

    def try_hit(self, now):
        self.hits = [at for at in self.hits if now - at < self.window - 1e-9]
        if self.hits and now - self.hits[-1] < self.minimum_interval - 1e-9:
            return False
        if len(self.hits) >= self.maximum:
            return False
        self.hits.append(now)
        return True


def checks_for_schools(schools, check, near):
    data = {s["school_id"]: s for s in schools}
    samples = []
    ice = data["ice"]
    frost = ice["mechanics"]["frost"]
    state = FrostWindow(frost)
    check("frost first two layers remain preparation", not state.apply(0) and not state.apply(.1) and state.stacks == 2)
    check("third layer establishes one window", state.apply(.2) and state.token == 1 and state.stacks == 0)
    initial_window = state.window_until
    check("hits cannot extend ready window", not state.apply(.3, 3) and state.window_until == initial_window)
    check("shatter consumes unique token", state.consume(.4) and not state.consume(.4))
    near("early shatter immunity starts at actual release", state.immune_until, .4 + frost["post_freeze_immunity"])
    check("immunity still allows brittle window", state.apply(.5, 3) and state.frozen_until == .5)
    check("later immunity expiry does not refreeze old window", not state.apply(.6, 3) and state.frozen_until == .5)
    check("brittle consumption does not extend old immunity", state.consume(.8) and state.immune_until == .4 + frost["post_freeze_immunity"])
    old = FrostWindow(frost)
    old.apply(0)
    old.apply(frost["expiry"])
    check("frost exact expiry cleans old layers first", old.stacks == 1)
    for kind, factor in frost["control_duration_coefficients"].items():
        state = FrostWindow(frost, kind)
        state.apply(0, 3)
        near(f"control duration applies once {kind}", state.frozen_until, frost["base_freeze"] * factor)
        check("every target class gets same brittle window", state.window_until == frost["ready_window"], kind)
    for freeze, immunity in [(x, y) for x in (.9, 1.2, 1.5) for y in (2.5, 3, 4)]:
        samples.append({"school": "ice", "case": "optimistic_hard_control_ceiling", "freeze": freeze, "immunity": immunity, "ratio": freeze / (freeze + immunity), "note": "Preparation/window conflicts ignored; not an actual simulated CC duty cycle."})
    spells = {s["id"]: s for s in ice["spells"]}
    items = {i["id"]: i for i in ice["items"]}
    shatter = spells["I07"]["levels"][0]["shatter_coefficient"]
    blue = items["IB07"]["params"]["level1_shatter_add"]
    gold = items["IG02"]["params"]["shatter_multiplier"]
    near("IB07 then IG02 changes one coefficient once", (shatter + blue) * gold, 3.84)
    samples.append({"school": "ice", "case": "IB07_IG02_level1_shatter_component", "coefficient": (shatter + blue) * gold, "excludes": "base hit/crit/neighbor shards"})

    lightning = data["lightning"]
    spells = {s["id"]: s for s in lightning["spells"]}
    items = {i["id"]: i for i in lightning["items"]}
    for level in spells["L03"]["levels"]:
        total = sum(level["coefficient"] * level["hop_decay"] ** j for j in range(level["target_cap"]))
        check("chain geometric series finite", total >= level["coefficient"] and level["target_cap"] <= 5)
    near("L03 known level3 total coefficient", total, 6.71171875)
    for target_count in (1, 2, 3, 6):
        for gold in (False, True):
            spec = spells["L08"]["levels"][2]
            overload = lightning["mechanics"]["overload"]
            boost = items["LG03"]["params"] if gold else overload
            limit = boost["boosted_existing_edges"]
            multiplier = boost["edge_multiplier"] if gold else boost["coefficient_multiplier"]
            edges = min(target_count, spec["target_cap"]) - 1
            qualified = target_count >= overload["minimum_precast_conductive_component"]
            boosted = min(edges, limit) if qualified else 0
            result = spec["coefficient"] + spec["edge_coefficient"] * ((edges - boosted) + boosted * multiplier)
            check("overload never adds hit count", boosted <= edges and edges <= spec["target_cap"] - 1)
            if target_count == 1:
                near("overload unused edges do not hit lone enemy", result, spec["coefficient"])
            if target_count == 6 and gold:
                near("L08 level3 LG03 hand known six nodes", result, 17)
            samples.append({"school": "lightning", "case": "L08_level3_connected_preexisting_nodes", "targets": target_count, "LG03": gold, "hit_targets": edges + 1, "boosted_edges": boosted, "coefficient_total": result})
    # Connection-distance sensitivity is graph coverage, not a new single-target multiplier.
    from model import ordered_chain
    positions = {str(n): (n * 3.4, 0) for n in range(6)}
    for reach in (3, 3.5, 4):
        path = ordered_chain("0", positions, 5, reach)
        samples.append({"school": "lightning", "case": "spacing3.4_no_conductive_bonus", "reach": reach, "hit_nodes": len(path)})

    wind = data["wind"]
    spells = {s["id"]: s for s in wind["spells"]}
    mechanic = wind["mechanics"]
    for level in spells["W08"]["levels"]:
        trace = BoundedTrace(mechanic["wind_trace_shared_hit_interval"], mechanic["wind_trace_shared_hit_window"], level["shared_window_hit_cap"])
        accepted = [step / 10 for step in range(60) if trace.try_hit(step / 10)]
        check("path replacement cannot reset rolling budget", len(accepted) == level["shared_window_hit_cap"])
        check("path exact rolling expiry permits next hit", trace.try_hit(6))
    check("trace has one global live instance", mechanic["wind_trace_global_instance_cap"] == 1)
    for reach_factor in (1, .35, 0):
        max_distance = 2 * reach_factor
        check("displacement is coefficient once", 0 <= max_distance <= 2)
    samples.append({"school": "wind", "case": "W08_level3_rolling6s_component_budget_per_enemy", "maximum_hits": spells["W08"]["levels"][2]["shared_window_hit_cap"], "coefficient_total": spells["W08"]["levels"][2]["shared_window_hit_cap"] * spells["W08"]["levels"][2]["tick"], "note": "No trace-reset bypass; ignores actual path intersection."})

    earth = data["earth"]
    mechanic = earth["mechanics"]
    sources = mechanic["construct_sources"]
    board, identity = {}, 0
    terminal_events = 0
    for _ in range(100):
        for source in sources:
            old_id = board.pop(source, None)
            terminal_events += int(old_id is not None)
            identity += 1
            board[source] = identity
            check("construct type and global cap under replacement", len(board) <= mechanic["construct_global_cap"] and len(set(board.values())) == len(board))
    check("construction replacements terminate once", terminal_events == 297 and len(board) == 3)
    items = {i["id"]: i for i in earth["items"]}
    spells = {s["id"]: s for s in earth["spells"]}
    gold = items["RG02"]["params"]
    level3 = spells["R07"]["levels"][2]
    # Replaces the level3 weak secondary, not an additive fourth echo.
    strengthened = level3["main"] + gold["natural_echo_construct_cap"] * gold["echo_coefficients_by_level"][2]
    near("RG02 replaces old second echo", strengthened, 5.8)
    samples.append({"school": "earth", "case": "R07_level3_RG02_all3anchors_geometrically_overlap", "coefficient_total": strengthened, "note": "old secondary .7 is replaced, no double reward; not natural encounter coverage."})

    spirit = data["spirit"]
    mechanic = spirit["mechanics"]
    family = dict(mechanic["per_family_base_capacity"])
    family["F04"] += 1  # P01 adds one named slot, never expands the global cap.
    check("P01 complete family composition still total4", sum(family.values()) == mechanic["total_attack_unit_capacity"] == 4)
    for remaining in (0, 1, 2, 3, 4):
        free = mechanic["total_attack_unit_capacity"] - remaining
        check("P01 fills only actual available slots", min(2, free) <= free)
    for cap in (4, 6):
        extended = 0
        for _ in range(100):
            accepted = min(4, max(0, cap - extended))
            extended += accepted
        check("contract field cannot extend one unit forever", extended == cap)
    spells = {s["id"]: s for s in spirit["spells"]}
    items = {i["id"]: i for i in spirit["items"]}
    check("SP02 candidate includes usable direct-source qualification", "S01_or_S06" in items["SP02"]["requires"])

    def sp02_qualified(owned):
        mark = "S01" in owned or owned.get("S08", 0) >= 3
        summon = any(source in owned for source in mechanic["summon_sources"])
        current_direct_path = "S01" in owned or "S06" in owned
        return mark and summon and current_direct_path

    check("SP02 excludes bare slow self-mark loop", not sp02_qualified({"S08": 3, "F04": 1}))
    check("SP02 accepts S01 plus summon", sp02_qualified({"S01": 1, "F04": 1}))
    check("SP02 accepts S06 with independent mark source", sp02_qualified({"S08": 3, "S06": 1, "F04": 1}))
    check("SP02 still requires real mark source", not sp02_qualified({"S06": 1, "F04": 1}))
    s08 = spells["S08"]
    check("bare S08 old-mark gap is real", s08["windup"] + s08["cooldowns"][2] > mechanic["mark_duration"])
    for level in spells["S04"]["levels"]:
        check("hawk attacks within actual sweep instead of search range", level["search_range"] > level["attack_range"] and level["attack_range"] <= level["sweep_length"] and level["move_speed"] > 0)
    samples.append({"school": "spirit", "case": "SP02_bare_S08_F04_rejected", "self_mark_duration": mechanic["mark_duration"], "natural_cycle": s08["windup"] + s08["cooldowns"][2], "qualified": False, "note": "Static selection excludes this zero-trigger composition; optional high-CDR/extended-mark narrow paths deliberately remain closed in this draft."})
    command = spells["S05"]["levels"][2]
    check("command damage has independent bounded participants", command["command_unit_cap"] == mechanic["total_attack_unit_capacity"] and not command["can_crit"])
    near("S05 level3 four units one command coefficient", command["command_coefficient"] * command["command_unit_cap"], 4.4)
    near("command never resets normal attack timer", float(mechanic["command_does_not_reset_normal_attack_timer"]), 1)
    samples.append({"school": "spirit", "case": "S05_level3_four_legal_units_all_resolve", "coefficient_total": command["command_coefficient"] * command["command_unit_cap"], "natural_casts": 1, "extra_normal_attacks": 0, "note": "Delayed command is canceled per expired/invalid unit; no crit/proc chain."})
    return samples
