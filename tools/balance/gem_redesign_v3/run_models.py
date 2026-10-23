"""Run only the four isolated proposal models; never launches Godot or migrates saves."""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
MODELS = [('common_model.py','common'),('fire_ice_lightning_model.py','fire-ice-lightning'),
          ('wind_earth_spirit_model.py','wind-earth-spirit'),('economy_model.py','economy')]

def main():
    cli=argparse.ArgumentParser()
    cli.add_argument('--output-root',type=Path,default=ROOT/'build/qa/gem-redesign-v3-20261022')
    args=cli.parse_args()
    output=args.output_root.resolve()
    if not output.is_relative_to((ROOT/'build/qa').resolve()):
        raise SystemExit('Output must remain in this project build/qa')
    for script,folder in MODELS:
        subprocess.run([sys.executable,str(HERE/script),'--output',str(output/folder)],cwd=ROOT,check=True)

if __name__=='__main__': main()
