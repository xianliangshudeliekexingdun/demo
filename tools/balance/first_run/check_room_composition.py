"""Review whole-room composition metrics; never starts or edits Godot."""
import hashlib
import json
from pathlib import Path
import re

from check_map_metrics import review as previous_review

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "data/balance_candidates/map_metrics_v2.json"
OUT = ROOT / "build/qa/room-composition-20261017"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def contains(outer, inner):
    return outer[0] <= inner[0] <= inner[2] <= outer[2] and outer[1] <= inner[1] <= inner[3] <= outer[3]


def review(config):
    base = load(SOURCE.parent / config["base_parameters"])
    viewport = (ROOT / config["viewport_reference"]).read_text(encoding="utf-8")
    vw = int(re.search(r"window/size/viewport_width=(\d+)", viewport)[1])
    vh = int(re.search(r"window/size/viewport_height=(\d+)", viewport)[1])
    visual = (ROOT / config["visual_reference"]["actor_call"]).read_text(encoding="utf-8")
    call = re.search(r"actor\(p,LINA,([\d.]+),Vector2\(([^,]+),([^\)]+)\)", visual)
    assert call, "Reinspect the existing character draw call"
    old_height, foot_x, foot_y = map(float, call.groups())
    radius, speed = base["player"]["radius"], base["player"]["move_speed"]
    floor, p = config["floor"], config["presentation"]
    w, d = floor["width"], floor["depth"]
    sx, sy = p["pixels_per_meter_x"], p["pixels_per_meter_depth"]
    cx, cy, h = vw / 2, p["floor_center_canvas_y"], p["actor_canvas_height"]
    assert min(w, d, sx, sy, radius, speed, h, floor["tile_size"]) > 0
    hud_free = [0, p["hud_top_reserved"], vw, vh - p["hud_bottom_reserved"]]
    rect = [cx - w * sx / 2, cy - d * sy / 2, cx + w * sx / 2, cy + d * sy / 2]
    player = [cx - (w / 2 - radius) * sx - h * foot_x,
              cy - (d / 2 - radius) * sy - h * foot_y,
              cx + (w / 2 - radius) * sx + h * (1 - foot_x),
              cy + (d / 2 - radius) * sy + h * (1 - foot_y)]
    walls = [rect[0] - p["side_wall_outer_margin"], rect[1] - p["rear_wall_canvas_height"],
             rect[2] + p["side_wall_outer_margin"], rect[3] + p["front_wall_canvas_overhang"]]
    assert sum(z["depth"] for z in config["zones_bottom_to_top"]) == d
    assert [z["id"] for z in config["zones_bottom_to_top"]] == ["entry", "combat", "portal"]
    zones = []
    low = -d / 2
    for z in config["zones_bottom_to_top"]:
        assert z["depth"] > 0
        high = low + z["depth"]
        zones.append(dict(z, world_low=low, world_high=high, area=w*z["depth"],
                          center=(low+high)/2, canvas_top=cy-high*sy, canvas_bottom=cy-low*sy))
        low = high
    portal_foot = cy - zones[-1]["center"] * sy
    portal = [cx - p["portal_max_canvas_width"] / 2, portal_foot - p["portal_max_canvas_height"],
              cx + p["portal_max_canvas_width"] / 2, portal_foot]
    boxes = {"floor": rect, "reference_player_extremes": player, "walls": walls, "portal_visual": portal}
    assert all(contains(hud_free, box) for box in boxes.values()), boxes
    assert contains([0, 0, 10, 10], [0, 0, 10, 10])
    assert not contains([0, 0, 10, 10], [-.1, 0, 10, 10])
    assert not contains([0, 0, 10, 10], [0, 0, 10, 10.1])
    assert zones[0]["canvas_top"] > zones[-1]["canvas_bottom"]
    assert not config["flow"]["portal_visible_in_combat"]
    assert config["flow"]["portal_appears_after_clear"] and config["flow"]["portal_usable_after_rewards"]
    assert config["flow"]["clear_disables_spikes_before_rewards"]
    assert config["flow"]["terminal_room_uses_final_settlement"]
    cross = [(w - 2 * radius) / speed, (d - 2 * radius) / speed]
    if (w, d, radius, speed) == (12, 14, .3, 5):
        assert abs(cross[0] - 2.28) < 1e-9 and abs(cross[1] - 2.68) < 1e-9
    baseline = previous_review(load(SOURCE.parent / config["previous_dimensions"]))
    saved = load(ROOT / "build/qa/map-metrics-20261017/results.json")
    assert baseline["rows"] == saved["rows"] and baseline["viewport"] == saved["viewport"]
    paths = [SOURCE, SOURCE.parent / config["base_parameters"], SOURCE.parent / config["ordinary_room_parameters"],
             SOURCE.parent / config["previous_dimensions"], ROOT / config["viewport_reference"],
             ROOT / config["visual_reference"]["actor_call"], Path(__file__), Path(__file__).with_name("check_map_metrics.py"),
             ROOT / config["diagram"]["reference"], ROOT / config["diagram"]["prompt"]]
    return {"model_version": "whole-room-geometry-1.0", "parameters": config, "viewport": [vw, vh],
            "player_reference": {"speed": speed, "radius": radius, "old_canvas_height": old_height,
                                 "proposed_canvas_height": h, "draw_scale_ratio": h/old_height, "foot_anchor": [foot_x, foot_y]},
            "zones": zones, "floor_area": w*d, "combat_area": next(z["area"] for z in zones if z["id"] == "combat"),
            "center_travel_size": [w-2*radius, d-2*radius], "straight_cross_seconds": cross,
            "floor_canvas_size": [w*sx, d*sy], "hud_free_canvas": hud_free, "canvas_boxes": boxes,
            "box_fit": {name: contains(hud_free, box) for name, box in boxes.items()},
            "legacy_metrics_reproduced": True, "previous_selected": baseline["rows"][1],
            "input_hashes": {str(path.relative_to(ROOT)): {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths},
            "limits": ["Generated concept is illustrative, not a pixel-to-meter blueprint or Godot screenshot",
                       "Proposed projection and sprite scale are unimplemented; actual FX, bars, bosses and occlusion need Godot pixel checks",
                       "No obstacle, spike or spawn coordinates, navigation, enemy AI or combat damage have been simulated",
                       "Band boundaries are visual allocation; opening safety is not permanent invulnerability"]}


def main():
    result = review(load(SOURCE))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"whole_floor": [result["parameters"]["floor"]["width"],result["parameters"]["floor"]["depth"]],
                      "combat_area": result["combat_area"], "cross_seconds": result["straight_cross_seconds"],
                      "box_fit": result["box_fit"], "legacy_reproduced": result["legacy_metrics_reproduced"],
                      "output": str(OUT / "results.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
