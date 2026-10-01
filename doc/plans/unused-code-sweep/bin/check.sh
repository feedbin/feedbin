#!/bin/bash
# Automated checks for one category (spec 7.1). Must run OUTSIDE the sandbox:
# the test server binds a port and the database is in OrbStack.
# Usage (from ~/Sites/feedbin):
#   bash $SWEEP/bin/check.sh baseline --assets   # step 0
#   bash $SWEEP/bin/check.sh 02-views            # after a category
#   bash $SWEEP/bin/check.sh 06-frontend --assets
# Prints one line per check while it runs (about 2-3 minutes in total).
# Logs go to $SWEEP/out/checks/<label>/. Exit status is 1 when any check is worse than the baseline.
source ~/.bash_profile >/dev/null 2>&1
set -uo pipefail
SWEEP="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${1:?label}"
ASSETS="${2:-}"
DIR="$SWEEP/out/checks/$LABEL"
BASE="$SWEEP/out/checks/baseline"
mkdir -p "$DIR"
cd ~/Sites/feedbin
worse=0

failures() { grep -hEA1 '^(Failure|Error):' "$@" 2>/dev/null | grep -oE '^[A-Z][A-Za-z0-9:]+#test_[A-Za-z0-9_?!]+' | sort -u; }

echo "[1/5] zeitwerk:check"
if bin/rails zeitwerk:check >"$DIR/zeitwerk.log" 2>&1; then echo "  ok"; else echo "  FAIL (see $DIR/zeitwerk.log)"; worse=1; fi

echo "[2/5] standardrb"
bundle exec standardrb --cache false --format json >"$DIR/standard.json" 2>"$DIR/standard.err"
ruby -rjson -e '
  counts = ->(p) { File.exist?(p) ? JSON.parse(File.read(p))["files"].to_h { |f| [f["path"], f["offenses"].size] } : {} }
  now = counts.(ARGV[0]); base = counts.(ARGV[1])
  up = now.select { |f, n| n > base.fetch(f, 0) }
  if up.empty? then puts "  ok (#{now.values.sum} offenses)" else up.each { |f, n| puts "  MORE OFFENSES #{f}: #{base.fetch(f, 0)} -> #{n}" }; exit 1 end
' "$DIR/standard.json" "$BASE/standard.json" || worse=1

if [ "$ASSETS" = "--assets" ]; then
  echo "[3/5] assets:precompile, then assets:clobber"
  if bin/rails assets:precompile >"$DIR/precompile.log" 2>&1; then echo "  ok"; else echo "  FAIL (see $DIR/precompile.log)"; worse=1; fi
  bin/rails assets:clobber >>"$DIR/precompile.log" 2>&1
else
  echo "[3/5] assets: skipped (pass --assets for steps 6-8)"
fi

echo "[4/5] unit and integration tests"
bundle exec rake >"$DIR/unit.log" 2>&1
grep -E '[0-9]+ runs, ' "$DIR/unit.log" | tail -1 | sed 's/^/  /'

echo "[5/5] system tests (stale assets removed first)"
rm -rf public/assets tmp/cache/assets
bin/rails test:system >"$DIR/system.log" 2>&1
grep -E '[0-9]+ runs, ' "$DIR/system.log" | tail -1 | sed 's/^/  /'

failures "$DIR/unit.log" "$DIR/system.log" >"$DIR/failures.txt"
if [ "$LABEL" != "baseline" ]; then
  new=$(comm -23 "$DIR/failures.txt" "$BASE/failures.txt")
  if [ -n "$new" ]; then echo "NEW FAILURES (not in baseline):"; echo "$new" | sed 's/^/  /'; worse=1; fi
  if ! grep -qE '[0-9]+ runs, ' "$DIR/unit.log" || ! grep -qE '[0-9]+ runs, ' "$DIR/system.log"; then
    echo "A SUITE DID NOT FINISH: read $DIR/unit.log and $DIR/system.log"; worse=1
  fi
fi
[ "$worse" = 0 ] && echo "RESULT: same as baseline" || echo "RESULT: WORSE than baseline"
exit "$worse"
