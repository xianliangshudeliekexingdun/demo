"""Item extension to the isolated first-run balance model, not game code."""
from collections import Counter, defaultdict
from contextlib import contextmanager
from copy import deepcopy

from model import Combat, EPS

ARTIFACT_MODEL_VERSION = "fire-items-1.1"
DIRECT_KINDS = {"bolt", "rain", "bomb", "beam", "wave"}
AREA_KINDS = {"rain", "vortex", "field"}


def resolve_catalog(base, raw):
    """Reuse approved generic amplitudes without another editable numeric copy."""
    catalog=deepcopy(raw)
    for item in catalog["items"].values():
        for key,value in list(item.items()):
            if isinstance(value,dict) and set(value)=={"base_ref"}:
                resolved=base
                for part in value["base_ref"].split("."):
                    resolved=resolved[part]
                if not isinstance(resolved,(int,float)):
                    raise ValueError("Base reference must resolve to a number")
                item[key]=resolved
    return catalog


def eligible(base, build, item):
    if item.get("required_spell"):
        return item["required_spell"] in build
    kinds = {base["spells"][sid]["kind"] for sid in build}
    active = kinds - {"passive"}
    offense = kinds - {"passive", "shield", "spirit"}
    rule = item.get("requirement")
    if not rule:
        return True
    if rule == "natural_direct_fire":
        return bool(kinds & DIRECT_KINDS)
    if rule == "two_area_spells":
        return len(kinds & AREA_KINDS) >= 2
    if rule in ("any_active_spell", "any_cooldown_spell"):
        return bool(active)
    if rule == "synergy_and_player_offense":
        return len(build) >= base["fire_synergy"]["distinct_spells"] and bool(offense)
    if rule == "spirit_and_player_offense":
        return "spirit" in kinds and bool(offense)
    if rule == "persistent_area_spell":
        return bool(kinds & {"vortex","field"}) or build.get("F03",0) == base["limits"]["spell_level"]
    raise ValueError(f"Unknown item requirement {rule}")


def derive_config(base, catalog, owned):
    """Derive a private encounter state; never mutate approved base parameters."""
    result = deepcopy(base)
    items = catalog["items"]
    for key, field in (("U01","health"),("U02","shield"),("U03","attack")):
        if key in owned:
            property_name = {"U01":"health_max_add","U02":"shield_max_add","U03":"attack_add"}[key]
            result["player"][field] += items[key][property_name]
    if "B02" in owned:
        result["player"]["crit_rate"] += items["B02"]["fire_crit_rate_add"]
    if "G01" in owned:
        result["player"]["fire_bonus"] += items["G01"]["fire_bonus_add"]
    s=result["spells"]
    if "B01" in owned:
        for level in s["F01"]["levels"]:
            level["radius"] *= items["B01"]["radius_multiplier"]
    if "B04" in owned:
        s["F04"]["duration"] += items["B04"]["duration_add"]
        for level in s["F04"]["levels"]:
            level["coefficient"] *= items["B04"]["normal_laser_damage_multiplier"]
    if "B06" in owned:
        for level in s["F06"]["levels"]:
            level["radius"] *= items["B06"]["radius_multiplier"]
    if "B07" in owned:
        for level in s["F07"]["levels"]:
            level["coefficient"] *= items["B07"]["main_center_damage_multiplier"]
    if "B08" in owned:
        s["F08"]["width"] *= items["B08"]["width_multiplier"]
    if "B10" in owned:
        for level in s["F10"]["levels"]:
            level["shield"] += items["B10"]["shield_restore_add"]
    return result


class ArtifactCombat(Combat):
    """All item events carry provenance, so extra results cannot recurse.

    Geometry probabilities remain explicit assumptions; no real paths or AI.
    An owned U01 starts each encounter at the chosen HP state, not a pickup heal.
    Callers passing current_health can model the no-free-heal acquisition rule.
    """
    def __init__(self, base, catalog, owned, build, profile, assumptions, enemies, seed, horizon, incoming=None, current_health=None):
        if len(set(owned)) != len(owned):
            raise ValueError("Duplicate unique item")
        self.owned = frozenset(owned)
        self.catalog = catalog
        self.items = catalog["items"]
        for key in owned:
            if not eligible(base,build,self.items[key]):
                raise ValueError(f"Ineligible item {key} for {build}")
        self.approved_base = base
        self.assumptions = assumptions
        self.ctx = {"origin":"system","natural":False,"root":None,"scale":1.0,"direct":False}
        self.root_serial = 0
        self.cast_targets = {}
        self.cast_aura = {}
        self.fixed_rain_roots = set()
        self.patch_roots = set()
        self.patches = []
        self.patch_last = {}
        self.zones = []
        self.slow_once = set()
        self.speed_once = set()
        self.slow_effects = defaultdict(list)
        self.speed_until = 0.0
        self.echo_counter = 0
        self.sync_ready = 0.0
        self.item_events = Counter()
        self.origin_damage = defaultdict(float)
        self.origin_effective = defaultdict(float)
        self.raw_accounted = defaultdict(float)
        self.extra_origins = Counter()
        self.event_total = 0
        self.maximum_queue = 0
        derived = derive_config(base,catalog,owned)
        p = dict(profile)
        if "B06" in owned:
            p["aura_stay"] = min(1,p["aura_stay"]*self.area_factor(self.items["B06"]["radius_multiplier"]))
        flags={}
        if "P01" in owned:
            flags["spirit_extra"] = self.items["P01"]["spirit_count_add"]
        if "P05" in owned:
            flags["fountain_interval"] = self.items["P05"]["interval"]
        super().__init__(derived,build,p,enemies,seed,horizon,flags,incoming)
        if current_health is not None:
            if not 0 <= current_health <= self.config["player"]["health"]:
                raise ValueError("Invalid current health")
            self.health = current_health

    def area_factor(self, scale):
        return 1+(scale*scale-1)*self.assumptions["geometry_benefit_capture"]

    @contextmanager
    def context(self, **overrides):
        saved = self.ctx
        self.ctx = dict(saved,**overrides)
        try:
            yield
        finally:
            self.ctx = saved

    def schedule(self, at, event, value):
        if event == "bomb" and self.ctx.get("root") is not None:
            self.cast_targets.setdefault(self.ctx["root"],list(value[1]))
        super().schedule(at,"provenance",(event,value,dict(self.ctx)))
        self.maximum_queue = max(self.maximum_queue,len(self.q))

    def snapshot(self, sid):
        aura=super().snapshot(sid)
        if self.ctx.get("root") is not None:
            self.cast_aura[self.ctx["root"]]=aura
        return aura

    def packet(self, delay, sid, ids, coefficient, hit, extra_hit, aura, tag=None, interval=0, token=None):
        root=self.ctx.get("root")
        if root is not None:
            self.cast_targets.setdefault(root,list(ids))
        direct = sid in self.config["spells"] and self.config["spells"][sid]["kind"] in DIRECT_KINDS and tag is None
        if sid=="F01" and "B01" in self.owned:
            extra_hit=min(1,extra_hit*self.area_factor(self.items["B01"]["radius_multiplier"]))
        if sid=="F06" and "B06" in self.owned:
            factor=self.area_factor(self.items["B06"]["radius_multiplier"])
            hit,extra_hit=min(1,hit*factor),min(1,extra_hit*factor)
        if sid=="F08" and "B08" in self.owned:
            factor=1+(self.items["B08"]["width_multiplier"]-1)*self.assumptions["geometry_benefit_capture"]
            extra_hit=min(1,extra_hit*factor)
        with self.context(direct=direct):
            if sid=="F03" and tag is None and "B03" in self.owned and root not in self.fixed_rain_roots:
                self.fixed_rain_roots.add(root)
                # Fix the first existing drop at the locked location; no homing.
                first_coefficient=coefficient*self.items["B03"].get("first_drop_damage_multiplier",1.0)
                super().packet(delay,sid,ids[:1],first_coefficient,self.assumptions["rain_stay_probability"],1,aura,tag,interval,token)
                if len(ids)>1:
                    super().packet(delay,sid,ids[1:],first_coefficient,hit*extra_hit,1,aura,tag,interval,token)
            else:
                super().packet(delay,sid,ids,coefficient,hit,extra_hit,aura,tag,interval,token)

    def extra_pool(self, sid_trigger):
        pool=[]
        for sid in self.states:
            if not self.legal(sid):
                continue
            if sid=="F09" and sid_trigger!="F09" and self.rng.random()>self.profile["wave_available"]:
                continue
            pool.append(sid)
        return pool

    def release(self, sid, natural):
        if not self.legal(sid):
            return False
        self.root_serial+=1
        origin="natural" if natural else self.ctx["origin"]
        scale=self.ctx.get("scale",1.0) if not natural else 1.0
        with self.context(origin=origin,natural=natural,root=self.root_serial,scale=scale,direct=False):
            success=super().release(sid,natural)
            if not success:
                return False
            root=self.ctx["root"]
            spec,level=self.definition(sid)
            offense=spec["kind"] not in {"passive","shield","spirit"}
            aura=self.cast_aura.get(root,0)
            ids=self.cast_targets.get(root,[])
            if sid in {"F03","F05","F06"} and ({"P03","G03"}&self.owned):
                start=self.time+(spec["impact_delay"] if sid=="F03" else 0)
                if sid=="F03":
                    duration=spec["impact_delay"]+(level["drops"]-1)*spec["interval"]+level["ground_duration"]
                elif sid=="F05":
                    duration=spec["duration"]+level["end_duration"]
                else:
                    duration=level["duration"]
                zone={"sid":sid,"ids":ids,"start":start,"end":self.time+duration,"field_token":self.field_token if sid=="F06" else None,"root":root,"aura":aura}
                self.zones.append(zone)
                persistent=sid!="F03" or level["ground_duration"]>0
                if natural and persistent and "G03" in self.owned:
                    with self.context(origin="G03",natural=False,scale=1.0):
                        self.schedule(zone["end"],"terminal",dict(zone))
            if natural:
                if "P04" in self.owned and self.natural_count % self.items["P04"]["natural_casts_per_extra"]==0:
                    self.book_procs+=1
                    self.item_events["P04_attempt"]+=1
                    pool=self.extra_pool(sid)
                    if pool:
                        with self.context(origin="book",natural=False,scale=self.items["P04"]["damage_multiplier"]):
                            self.schedule(self.time,"extra",self.rng.choice(pool))
                if offense and "G01" in self.owned:
                    self.echo_counter+=1
                    if self.echo_counter % self.items["G01"]["offensive_casts_per_echo"]==0:
                        with self.context(origin="echo",natural=False,scale=self.items["G01"]["echo_damage_multiplier"]):
                            self.schedule(self.time,"extra",sid)
                            self.item_events["G01_echo"]+=1
                if offense and "G02" in self.owned and self.time<self.spirit_until-EPS and self.time>=self.sync_ready-EPS:
                    self.sync_ready=self.time+self.items["G02"]["shared_cooldown"]
                    _,spirit_level=self.definition("F04")
                    primary=self.target()
                    laser_targets=self.cohort(primary) if spirit_level["pierce"] else [primary]
                    with self.context(origin="G02",natural=False,scale=1.0):
                        self.packet(0,"G02",laser_targets,self.items["G02"]["coefficient"],self.profile["direct_hit"],self.profile["line_extra"],aura)
                    self.item_events["G02_laser"]+=1
            else:
                self.extra_origins[origin]+=1
            return True

    def active_area_kinds(self, target_id):
        kinds=set()
        for z in self.zones:
            if z["start"]-EPS<=self.time<z["end"]-EPS and target_id in z["ids"] and (z["field_token"] is None or z["field_token"]==self.field_token):
                kinds.add(z["sid"])
        return kinds

    def damage_modifiers(self, sid, target_id):
        multiplier=self.ctx.get("scale",1.0)
        crit_add=0
        if sid=="F07" and "B07" in self.owned and self.ctx.get("main_center"):
            crit_add=self.items["B07"]["main_center_crit_multiplier_add"]
        if "P03" in self.owned and len(self.active_area_kinds(target_id))>=self.items["P03"]["required_distinct_areas"]:
            if self.rng.random()<self.assumptions["overlap_observed_fraction"]:
                multiplier*=1+self.items["P03"]["fire_vulnerability"]
                self.item_events["P03_amplified_hit"]+=1
        return multiplier,crit_add

    def add_slow(self,target_id,fraction,duration):
        self.slow_effects[target_id].append((fraction,self.time+duration))

    def slow_at(self,target_id):
        return max((v for v,end in self.slow_effects[target_id] if end>self.time+EPS),default=0)

    def move_speed(self):
        bonus=self.items["B09"]["move_speed_bonus"] if "B09" in self.owned and self.time<self.speed_until-EPS else 0
        return self.config["player"]["move_speed"]*(1+bonus)

    def after_damage(self,sid,target_id,critical,actual,aura):
        origin=self.ctx["origin"]
        raw=self.damage[sid]-self.raw_accounted[sid]
        self.raw_accounted[sid]=self.damage[sid]
        self.origin_damage[origin]+=raw
        self.origin_effective[origin]+=actual
        root=self.ctx.get("root")
        if actual<=0:
            return
        if sid=="F05" and "B05" in self.owned and (root,target_id) not in self.slow_once:
            self.slow_once.add((root,target_id))
            self.add_slow(target_id,self.items["B05"]["slow"],self.items["B05"]["duration"])
            self.item_events["B05_slow"]+=1
        if sid=="F09":
            _,level=self.definition(sid)
            if level["slow"]:
                self.add_slow(target_id,level["slow"],level["slow_duration"])
            if "B09" in self.owned and root not in self.speed_once:
                self.speed_once.add(root)
                self.speed_until=max(self.speed_until,self.time+self.items["B09"]["duration"])
                self.item_events["B09_speed"]+=1
        if "P02" in self.owned and self.ctx["natural"] and self.ctx.get("direct") and critical and root not in self.patch_roots:
            self.patch_roots.add(root)
            item=self.items["P02"]
            patch={"ids":self.cohort(target_id),"first":self.time+item["interval"],"end":self.time+item["duration"],"aura":aura}
            self.patches.append(patch)
            self.item_events["P02_patch"]+=1
            with self.context(origin="P02",natural=False,direct=False,scale=1.0):
                for i in range(1,round(item["duration"]/item["interval"])+1):
                    self.schedule(self.time+i*item["interval"],"patch_tick",None)

    def patch_tick(self):
        item=self.items["P02"]
        active=[p for p in self.patches if p["first"]<=self.time+EPS and p["end"]>=self.time-EPS]
        for target in self.alive():
            tid=target["id"]
            covering=[p for p in active if tid in p["ids"]]
            if not covering or self.time-self.patch_last.get(tid,-1e12)<item["interval"]-EPS:
                continue
            self.patch_last[tid]=self.time
            best=max(covering,key=lambda p:p["aura"])
            primary=any(p["ids"][0]==tid for p in covering)
            chance=self.profile["zone_hit"]*(1 if primary else self.profile["area_extra"])
            if self.rng.random()<chance:
                self.deal("P02",tid,item["coefficient"],best["aura"])

    def event(self,event,value):
        if event!="provenance":
            return self.inner_event(event,value)
        event,value,ctx=value
        self.event_total+=1
        saved=self.ctx
        self.ctx=ctx
        try:
            self.inner_event(event,value)
        finally:
            self.ctx=saved

    def inner_event(self,event,value):
        if event=="spirit":
            with self.context(origin="spirit",natural=False,direct=False,scale=1.0):
                return super().event(event,value)
        if event=="bomb":
            sid,ids,aura,aftershock=value
            _,level=self.definition(sid)
            for i,target_id in enumerate(ids):
                if self.rng.random()>self.profile["bomb_hit"]*(self.profile["area_extra"] if i else 1):
                    continue
                center=i==0 and self.rng.random()<self.profile["bomb_center"]
                coefficient=level["aftershock"]*(1 if center else 0.5) if aftershock else level["coefficient"] if center else level["outer"]
                with self.context(direct=True,main_center=center and not aftershock):
                    self.deal(sid,target_id,coefficient,aura)
            return
        if event=="terminal":
            zone=value
            if zone["field_token"] is not None and zone["field_token"]!=self.field_token:
                self.item_events["G03_cancelled_replacement"]+=1
                return
            if self.alive():
                self.packet(0,"G03",zone["ids"],self.items["G03"]["coefficient"],self.profile["zone_hit"],self.profile["area_extra"],zone["aura"])
                self.item_events["G03_explosion"]+=1
            return
        if event=="patch_tick":
            return self.patch_tick()
        if event=="fountain":
            for sid,state in self.states.items():
                if not state["casting"] and state["ready"]>self.time:
                    state["ready"]=self.time+(state["ready"]-self.time)*self.items["P05"]["remaining_cooldown_multiplier"]
                    self.schedule(state["ready"],"try",sid)
            self.schedule(self.time+self.items["P05"]["interval"],"fountain",None)
            self.item_events["P05_pulse"]+=1
            return
        return super().event(event,value)

    def run(self):
        result=super().run()
        if "P02" in self.owned:
            assert self.item_events["P02_patch"]<=self.natural_count
        if "G01" in self.owned:
            assert self.item_events["G01_echo"]<=self.echo_counter//self.items["G01"]["offensive_casts_per_echo"]
        assert self.item_events["G02_laser"]<=self.natural_count
        assert self.item_events["G03_explosion"]+self.item_events["G03_cancelled_replacement"]<=self.natural_count
        result.update(item_events=dict(self.item_events),damage_by_origin=dict(self.origin_damage),effective_by_origin=dict(self.origin_effective),extra_by_origin=dict(self.extra_origins),event_count=self.event_total,maximum_queue=self.maximum_queue)
        return result
