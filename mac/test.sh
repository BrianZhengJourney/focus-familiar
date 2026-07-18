#!/bin/bash
# Compile and run Mimo's unit tests.
#
# Each test in mac/tests/ is its own `@main` executable, so they cannot be
# linked together — every test needs its own subset of the app sources. That
# map lives here, and only here. When a source file grows a new dependency,
# the matching entry below must grow with it or this script fails loudly.
#
#   mac/test.sh              # compile + run every unit test
#   mac/test.sh custom_pet   # only tests whose name matches the filter
set -uo pipefail
cd "$(dirname "$0")"
source ./common.sh

FILTER="${1:-}"
OUT="${TMPDIR:-/private/tmp}/mimo-tests"
mkdir -p "$OUT" "$MODULE_CACHE"

# test name -> app sources it needs (space separated)
test_sources() {
  case "$1" in
    panel_geometry_test)        echo "panel_geometry.swift" ;;
    activity_log_test)          echo "activity_log.swift" ;;
    edit_menu_test)             echo "app_menu.swift" ;;
    generation_ledger_test)     echo "generation_ledger.swift" ;;
    style_reference_test)       echo "style_reference.swift" ;;
    generation_draft_test)      echo "generation_draft.swift" ;;
    character_sheet_test)       echo "character_sheet.swift" ;;
    custom_pet_test)            echo "custom_pet.swift character_sheet.swift" ;;
    reference_preprocessor_test) echo "reference_preprocessor.swift" ;;
    pet_generation_test)        echo "custom_pet.swift character_sheet.swift generation_draft.swift \
                                      generation_ledger.swift style_reference.swift \
                                      reference_preprocessor.swift pet_generation.swift" ;;
    # Compile-only: a paid end-to-end smoke test and a diagnostic CLI. Neither
    # is safe to run unattended, but both must keep compiling.
    live_generation_loop)       echo "custom_pet.swift character_sheet.swift \
                                      reference_preprocessor.swift pet_generation.swift" ;;
    app_lifecycle_probe)        echo "" ;;
    *)                          return 1 ;;
  esac
}

# these compile but are never executed here
compile_only() {
  case "$1" in
    live_generation_loop|app_lifecycle_probe) return 0 ;;
    *) return 1 ;;
  esac
}

frameworks=()
for framework in "${APP_FRAMEWORKS[@]}"; do frameworks+=(-framework "$framework"); done

pass=0; fail=0; failed_names=()
for path in tests/*.swift; do
  name="$(basename "$path" .swift)"
  [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue

  if ! sources="$(test_sources "$name")"; then
    echo "✗ $name — no source list in test.sh (add one)"
    fail=$((fail + 1)); failed_names+=("$name"); continue
  fi

  binary="$OUT/$name"
  # shellcheck disable=SC2086
  if ! swiftc -module-cache-path "$MODULE_CACHE" $sources "$path" -o "$binary" \
       "${frameworks[@]}" 2>"$OUT/$name.log"; then
    echo "✗ $name — compile failed"
    sed 's/^/    /' "$OUT/$name.log"
    fail=$((fail + 1)); failed_names+=("$name"); continue
  fi

  if compile_only "$name"; then
    echo "· $name — compiled (not run)"
    pass=$((pass + 1)); continue
  fi

  # tests resolve fixture paths like `mac/assets/...` relative to the repo root
  if (cd .. && "$binary") >"$OUT/$name.out" 2>&1; then
    echo "✓ $name"
    pass=$((pass + 1))
  else
    echo "✗ $name — failed"
    sed 's/^/    /' "$OUT/$name.out"
    fail=$((fail + 1)); failed_names+=("$name")
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "all green — $pass passed"
else
  echo "$fail failed (${failed_names[*]}), $pass passed"
  exit 1
fi
