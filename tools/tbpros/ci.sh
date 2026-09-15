#!/usr/bin/env bash
# Local/CI equivalent gate. Install locked dependencies and solc before calling; no RPC needed.
set -euo pipefail
: "${TBPROS_SOLC:?Set TBPROS_SOLC to the approved native solc 0.8.28 executable}"
mkdir -p cache/tbpros-hardening
export FOUNDRY_PROFILE=tbpros
forge build --use "$TBPROS_SOLC" --offline --force > cache/tbpros-hardening/build.log 2>&1
forge test --use "$TBPROS_SOLC" --offline -vv > cache/tbpros-hardening/core-tests.log 2>&1
# Historical regressions have their own default profile; do not accidentally inherit tbpros.
env -u FOUNDRY_PROFILE forge test --root test/tbpros/security-regression --use "$TBPROS_SOLC" --offline -vv > cache/tbpros-hardening/regression-tests.log 2>&1
python3 -m unittest discover -s reference -p '*_model.py' -v > cache/tbpros-hardening/python-tests.log 2>&1
node node_modules/hardhat/dist/src/cli.js --config hardhat.tbpros.config.ts compile --build-profile production --force > cache/tbpros-hardening/hardhat-build.log 2>&1
node tools/tbpros/core-manifests.mjs > cache/tbpros-hardening/manifests.log
python3 tools/tbpros/storage-manifest.py >> cache/tbpros-hardening/manifests.log
# Never --update in CI: regenerated current evidence must match reviewed ABI/storage snapshots.
python3 tools/tbpros/hardening-guards.py > cache/tbpros-hardening/guards.log
cat cache/tbpros-hardening/guards.log
