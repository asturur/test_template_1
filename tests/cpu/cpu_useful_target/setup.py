"""Frozen accepted 5F, research observers only; no RTL overlay."""
from pathlib import Path
import subprocess,shutil,hashlib,json
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
BASE='8e70b1ebc16486443d09f008384b4c0bc41c071c'
def overlay(destination,candidate=False):
 assert not candidate
