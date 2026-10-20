"""Check proposed room dimensions; no Godot invocation or game mutation."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "data/balance_candidates/map_metrics_v1.json"
OUT = ROOT / "build/qa/map-metrics-20261017"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def review(config):
    base = load(SOURCE.parent / config["base_parameters"])
    viewport = (ROOT / config["viewport_reference"]).read_text(encoding="utf-8")
    vw = int(re.search(r"window/size/viewport_width=(\d+)", viewport)[1])
    vh = int(re.search(r"window/size/viewport_height=(\d+)", viewport)[1])
    visual = (ROOT / config["visual_reference"]["actor_call"]).read_text(encoding="utf-8")
    match = re.search(r"actor\(p,LINA,([\d.]+),Vector2\(([^,]+),([^\)]+)\)", visual)
    assert match, "Existing actor reference changed; inspect the actual draw call"
    height, foot_x, foot_y = map(float, match.groups())
    radius, speed = base["player"]["radius"], base["player"]["move_speed"]
    pres = config["presentation"]
    sx, sy = pres["pixels_per_meter_x"], pres["pixels_per_meter_depth"]
    cx, cy = vw / 2, pres["floor_center_canvas_y"]
    assert min(sx, sy, speed, radius) > 0
    assert config["floor"]["tile_size"] > 0
    rows = []
    # The two alternatives are comparison fixtures, not runtime defaults.
    for width, depth in ((16, 8), (config["floor"]["width"], config["floor"]["depth"]), (20, 10)):
        left = cx - (width / 2 - radius) * sx - height * foot_x
        right = cx + (width / 2 - radius) * sx + height * (1 - foot_x)
        top = cy - (depth / 2 - radius) * sy - height * foot_y
        bottom = cy + (depth / 2 - radius) * sy + height * (1 - foot_y)
        rows.append({"width": width, "depth": depth, "floor_area": width * depth,
                     "floor_pixels": [width * sx, depth * sy],
                     "center_travel_size": [width - 2 * radius, depth - 2 * radius],
                     "horizontal_cross_seconds": (width - 2 * radius) / speed,
                     "vertical_cross_seconds": (depth - 2 * radius) / speed,
                     "player_sprite_extents_at_extremes": [left, top, right, bottom],
                     "sprite_fits_between_hud": left >= 0 and right <= vw and top >= pres["hud_top_reserved"] and bottom <= vh - pres["hud_bottom_reserved"],
                     "top_margin_to_hud": top - pres["hud_top_reserved"],
                     "bottom_margin_to_hud": vh - pres["hud_bottom_reserved"] - bottom})
    selected = rows[1]
    assert all(value > 0 for value in selected["center_travel_size"])
    assert selected["sprite_fits_between_hud"], "Room crops the reference actor or HUD"
    assert pres["hud_top_reserved"] < cy - config["floor"]["depth"] / 2 * sy
    assert cy + config["floor"]["depth"] / 2 * sy < vh - pres["hud_bottom_reserved"]
    # Independent selected-case hand anchor from the design: (18-0.6)/5, (9-0.6)/5.
    if (config["floor"]["width"], config["floor"]["depth"], radius, speed) == (18, 9, .3, 5):
        assert abs(selected["horizontal_cross_seconds"] - 3.48) < 1e-9
        assert abs(selected["vertical_cross_seconds"] - 1.68) < 1e-9
    paths = [SOURCE, SOURCE.parent / config["base_parameters"], SOURCE.parent / config["ordinary_room_parameters"],
             ROOT / config["viewport_reference"], ROOT / config["visual_reference"]["actor_call"], Path(__file__)]
    return {"method": "deterministic_geometry_and_constant_speed_arithmetic", "viewport": [vw, vh],
            "units": {"distance": "m", "time": "s", "canvas": "logical_px"},
            "player_reference": {"speed": speed, "radius": radius, "draw_height": height, "foot_anchor": [foot_x, foot_y]},
            "parameters": config, "rows": rows,
            "input_hashes": {str(p.relative_to(ROOT)): {"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths},
            "limits": ["Projection and HUD reservations are proposed; no Godot visual verification",
                       "Reference actor rectangle only; staff, bars, bosses, shadows and FX still require pixel checks",
                       "Straight crossing times exclude obstacles, spikes and enemies; no layout or safe path simulation"]}


def main():
    result = review(load(SOURCE))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"selected": result["rows"][1], "output": str(OUT / "results.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
