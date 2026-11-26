#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${GL4ES_TEST_BUILD_DIR:-${TMPDIR:-/tmp}/gl4es116_e2e_build}"
PSA_DIR="${BUILD_DIR}/psa"

rm -rf "${PSA_DIR}"
mkdir -p "${BUILD_DIR}" "${PSA_DIR}"

CMAKE_ARGS=(
  -S "${SCRIPT_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  -DENABLE_SANITIZERS=ON
)

if [[ "${1:-}" == "--pre-m1-smoke" ]]; then
  CMAKE_ARGS+=(-DGL4ES_PRE_M1_SMOKE=ON)
fi

cmake "${CMAKE_ARGS[@]}"
cmake --build "${BUILD_DIR}" -j4

export LIBGL_PSA_FOLDER="${PSA_DIR}"
export LIBGL_NOBANNER=1
export AMETHYST_GL4ES_ERROR_TRACE=0
export LIBGL_BEGINEND=1

if [[ "$(uname -s)" == "Linux" ]]; then
  export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1}"
fi

ctest --test-dir "${BUILD_DIR}" --output-on-failure

HARNESS_BIN="${BUILD_DIR}/bin/gl4es116_test_harness"
if [[ "${1:-}" != "--pre-m1-smoke" ]] && [[ -x "${HARNESS_BIN}" ]]; then
  echo "=== Verifying 2GB (low) vs 6GB (high) METRIC comparison ==="
  LOW_OUT="$("${HARNESS_BIN}" --suite tier4_village_low)"
  HIGH_OUT="$("${HARNESS_BIN}" --suite tier4_village_high)"
  echo "${LOW_OUT}"
  echo "${HIGH_OUT}"
  python3 -c '
import sys
low_out, high_out = sys.argv[1], sys.argv[2]
def parse_metric(txt):
    for line in txt.splitlines():
        if line.startswith("METRIC "):
            kv = dict(p.split("=", 1) for p in line.split()[1:] if "=" in p)
            return {k: float(v) for k, v in kv.items() if k != "profile"}
    raise RuntimeError("Missing METRIC line")
lm, hm = parse_metric(low_out), parse_metric(high_out)
assert lm["budget_bytes"] < hm["budget_bytes"]
assert lm["fpe_cache_max_entries"] < hm["fpe_cache_max_entries"]
assert lm["psa_max_entries"] < hm["psa_max_entries"]
assert lm["psa_max_bytes"] < hm["psa_max_bytes"]
assert lm["fpe_cache_entries"] <= 192 < hm["fpe_cache_entries"] <= 1024
assert lm["peak_scratch_bytes"] <= lm["budget_bytes"]
assert lm["peak_scratch_bytes"] <= lm["color_scratch_cap"]
assert lm["peak_scratch_bytes"] < hm["peak_scratch_bytes"]
assert lm["max_batch_ms"] < 2000.0 and hm["max_batch_ms"] < 2000.0
print("Cross-profile METRIC comparison PASSED")
' "${LOW_OUT}" "${HIGH_OUT}"
fi

if [[ "$(uname -s)" == "Darwin" ]] && command -v leaks >/dev/null 2>&1; then
  NOLEAK_DIR="${BUILD_DIR}_noleak"
  mkdir -p "${NOLEAK_DIR}" "${NOLEAK_DIR}/psa"
  NOLEAK_ARGS=(
    -S "${SCRIPT_DIR}"
    -B "${NOLEAK_DIR}"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DENABLE_SANITIZERS=OFF
  )
  if [[ "${1:-}" == "--pre-m1-smoke" ]]; then
    NOLEAK_ARGS+=(-DGL4ES_PRE_M1_SMOKE=ON)
  fi
  cmake "${NOLEAK_ARGS[@]}"
  cmake --build "${NOLEAK_DIR}" -j4
  NOLEAK_BIN="${NOLEAK_DIR}/bin/gl4es116_test_harness"
  if [[ -x "${NOLEAK_BIN}" ]]; then
    echo "=== Running macOS leaks --atExit check on non-ASan binary ==="
    leaks --atExit -- "${NOLEAK_BIN}" --suite tier1_leaks
    if [[ "${1:-}" != "--pre-m1-smoke" ]]; then
      leaks --atExit -- "${NOLEAK_BIN}" --suite tier4_multicontext
    fi
  fi
fi

echo "=== Running Python structural & invariant suite ==="
python3 "${REPO_ROOT}/tests/test_gl4es116_invariants.py"
