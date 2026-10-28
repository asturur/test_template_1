.PHONY: sim sim-upstream sim-compat sim-firmware

PYTHON ?= python3
export FIRMWARE

sim:
	$(PYTHON) sim/run.py

sim-upstream:
	$(PYTHON) sim/run.py --upstream --cpu-variant upstream

sim-compat:
	$(PYTHON) sim/run.py --require-compatible

sim-firmware:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE"

BOOT_PROFILE ?= amd16
export BOOT_PROFILE
.PHONY: sim-firmware-explore
sim-firmware-explore:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE"

.PHONY: sim-upstream-patched sim-unmodified sim-firmware-ideal-clocks
sim-upstream-patched:
	$(PYTHON) sim/run.py --upstream --cpu-variant ngage

sim-unmodified:
	$(PYTHON) sim/run.py --cpu-variant upstream

sim-firmware-ideal-clocks:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE" --ideal-clocks

.PHONY: sim-rtl-lint inspect-boot
sim-rtl-lint:
	$(PYTHON) sim/run.py --rtl-lint

inspect-boot:
	$(PYTHON) sim/inspect_boot.py

ORACLE_PYTHON ?= build/oracle/venv/bin/python
.PHONY: oracle-setup sim-oracle sim-oracle-ideal-clocks sim-oracle-lcd sim-firmware-lcd
oracle-setup:
	mkdir -p scratch/python-tmp scratch/pip-cache build/oracle
	$(PYTHON) -m venv build/oracle/venv
	TMPDIR="$(CURDIR)/scratch/python-tmp" PIP_CACHE_DIR="$(CURDIR)/scratch/pip-cache" $(ORACLE_PYTHON) -m pip install -r sim/requirements-oracle.txt

sim-oracle:
	$(ORACLE_PYTHON) sim/oracle.py

sim-oracle-ideal-clocks:
	$(ORACLE_PYTHON) sim/oracle.py --ideal-clocks

sim-oracle-lcd:
	$(ORACLE_PYTHON) sim/oracle.py --ideal-clocks --lcd-probe --no-instruction-trace --max-instructions 50000000

sim-firmware-lcd:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE" --ideal-clocks --lcd-probe --compact-trace --max-cycles 180000000

.PHONY: sim-oracle-check
sim-oracle-check:
	$(ORACLE_PYTHON) sim/test_oracle.py

.PHONY: inspect-flash-scan
inspect-flash-scan:
	$(PYTHON) sim/inspect_flash_scan.py

.PHONY: firmware-inventory
firmware-inventory:
	$(PYTHON) sim/inventory_firmware.py

.PHONY: prepare-rom-extension check-rom-extension sim-oracle-extension sim-firmware-extension
prepare-rom-extension:
	$(PYTHON) sim/rom_extension.py

check-rom-extension:
	$(PYTHON) sim/test_rom_extension.py

sim-oracle-extension:
	$(ORACLE_PYTHON) sim/oracle.py --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --no-instruction-trace --max-instructions 50000000

sim-firmware-extension:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE" --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --compact-trace --max-cycles 200000000

# Explicit analog scenario: the sample is an assumption, printed and recorded.
UEM_ADC ?= 6=512
.PHONY: sim-firmware-adc sim-oracle-adc
sim-firmware-adc:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE" --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --uem-adc "$(UEM_ADC)" --compact-trace --max-cycles 1000000000

sim-oracle-adc:
	$(ORACLE_PYTHON) sim/oracle.py --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --uem-adc "$(UEM_ADC)" --mmu-reference --fast-rom-reference --compact-bus --no-instruction-trace --max-instructions 500000000

.PHONY: inspect-firmware-digest
inspect-firmware-digest:
	$(PYTHON) sim/inspect_firmware_digest.py

.PHONY: inspect-digest-variants
inspect-digest-variants:
	$(PYTHON) sim/inspect_digest_variants.py

.PHONY: check-digest-probe sim-oracle-digest-probe sim-firmware-digest-probe
DIGEST_PROBE ?= both
check-digest-probe:
	$(PYTHON) sim/test_digest_probe.py

sim-oracle-digest-probe:
	$(ORACLE_PYTHON) sim/oracle.py --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --uem-adc "$(UEM_ADC)" --digest-probe "$(DIGEST_PROBE)" --mmu-reference --fast-rom-reference --compact-bus --no-instruction-trace --max-instructions 500000000

sim-firmware-digest-probe:
	$(PYTHON) sim/run.py --firmware "$$FIRMWARE" --boot-profile "$$BOOT_PROFILE" --ideal-clocks --lcd-probe --rom-extension --boot-io-probe --uem-adc "$(UEM_ADC)" --digest-probe "$(DIGEST_PROBE)" --compact-trace --max-cycles 1000000000

.PHONY: sim-ldm-replay
# Known failing regression: returns nonzero until the cold-cache replay is fixed.
sim-ldm-replay:
	$(PYTHON) sim/check_ldm_replay.py
