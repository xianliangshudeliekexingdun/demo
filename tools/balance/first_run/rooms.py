"""Normal-room composition and a bounded reinforcement extension of the item model."""
from __future__ import annotations

from collections import Counter

from artifacts import ArtifactCombat
from model import EPS, normal_stats

ROOM_MODEL_VERSION = "normal-rooms-1.0"


def composition(row):
    return sum((Counter(pack) for pack in row["packs"]), Counter())


def room_budget(base, config, row):
    counts = composition(row)
    stage = next(i for i,s in enumerate(base["normal_stages"]) if s["from"]<=row["room"]<=s["to"])
    sizes = [sum(p.values()) for p in row["packs"]]
    threshold = config["spawn"]["next_batch_when_alive_at_most"]
    peak = max([sizes[0]]+[min(threshold,sum(sizes[:i]))+size for i,size in enumerate(sizes[1:],1)])
    return {"room":row["room"],"counts":dict(counts),"total":sum(counts.values()),"batch_sizes":sizes,
            "total_health":sum(normal_stats(base,k,row["room"])["health"]*n for k,n in counts.items()),
            "alive_cap":config["spawn"]["alive_cap_by_normal_stat_stage"][stage],"peak_upper_bound":peak}


class RoomCombat(ArtifactCombat):
    """Preserve spell clocks across waves; no positions or enemy attack AI."""
    def __init__(self, base, catalog, owned, build, profile, assumptions, row, spawn, cap, seed, horizon, preview_override=None):
        self.row, self.spawn = row, spawn
        self.packs = row["packs"]
        self.next_pack = 0
        self.previewing = None
        self.cap = cap
        self.preview = spawn["preview_seconds"] if preview_override is None else preview_override
        self.peak = 0
        self.spawn_log = []
        self.empty_gaps = 0.0
        self.gap_started = 0.0
        super().__init__(base,catalog,owned,build,profile,assumptions,[],seed,horizon)
        self.start_preview()

    def start_preview(self):
        if self.previewing is not None or self.next_pack>=len(self.packs):
            return
        if self.next_pack and len(self.alive())>self.spawn["next_batch_when_alive_at_most"]:
            return
        count=sum(self.packs[self.next_pack].values())
        if len(self.alive())+count>self.cap:
            return
        self.previewing=self.next_pack
        self.schedule(self.time+self.preview,"activate_pack",self.next_pack)

    def legal(self, sid):
        if sid=="F10" and self.health>EPS and (self.alive() or self.next_pack<len(self.packs)):
            return self.shield<self.config["player"]["shield"]-EPS
        return super().legal(sid)

    def deal(self, sid, target_id, coefficient, aura):
        super().deal(sid,target_id,coefficient,aura)
        if self.end=="clear" and (self.next_pack<len(self.packs) or self.previewing is not None):
            self.end=None
        if not self.alive() and self.gap_started is None and self.end!="clear":
            self.gap_started=self.time
        if self.end!="dead":
            self.start_preview()

    def inner_event(self, event, value):
        if event=="try" and value!="F10" and not self.alive() and self.next_pack<len(self.packs):
            # Base familiar polling uses EPS when no targets; wake once on birth instead.
            return
        if event=="activate_pack":
            if value!=self.previewing or value!=self.next_pack:
                return
            if self.gap_started is not None:
                self.empty_gaps+=self.time-self.gap_started
                self.gap_started=None
            pack=self.packs[value]
            for kind,count in pack.items():
                for _ in range(count):
                    self.add_target(dict(normal_stats(self.approved_base,kind,self.row["room"]),kind=kind,pack=value))
            self.next_pack+=1
            self.previewing=None
            self.peak=max(self.peak,len(self.alive()))
            if self.peak>self.cap:
                raise AssertionError("Simultaneous enemy cap exceeded")
            self.spawn_log.append({"pack":value+1,"time":self.time,"alive":len(self.alive()),"spawned":dict(pack)})
            for sid,state in self.states.items():
                if not state["casting"]:
                    self.schedule(max(self.time,state["ready"]),"try",sid)
            self.start_preview()
            return
        return super().inner_event(event,value)

    def run(self):
        result=super().run()
        if result["status"]=="clear":
            assert self.next_pack==len(self.packs) and self.previewing is None
        result.update(spawn_log=self.spawn_log,peak_alive=self.peak,empty_enemy_seconds=self.empty_gaps,
                      spawned=sum(sum(p["spawned"].values()) for p in self.spawn_log))
        return result
