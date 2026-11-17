"""One earlier registered-ALU probe on the accepted 5J P1-load prototype."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE='8e70b1ebc16486443d09f008384b4c0bc41c071c'
MODE='lookup'
def overlay(destination,candidate):
    if candidate:
        source=(ROOT/'tests/cpu/cpu_load_pipeline' if MODE=='p1' else HERE)/'rtl/arm/zap_core.sv'
        shutil.copyfile(source,destination/'rtl/arm/zap_core.sv')
