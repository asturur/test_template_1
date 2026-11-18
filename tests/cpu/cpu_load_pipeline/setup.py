"""Exact 5F versus one isolated P1 ordinary-load ownership change."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE='8e70b1ebc16486443d09f008384b4c0bc41c071c'
def overlay(destination,candidate):
    if candidate:
        shutil.copyfile(HERE/'rtl/arm/zap_core.sv',destination/'rtl/arm/zap_core.sv')
