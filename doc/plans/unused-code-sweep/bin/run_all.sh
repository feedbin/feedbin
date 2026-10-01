#!/bin/bash
# Runs every finder in sweep order. Use for step 0 (baseline counts) and step 9 (final pass).
# Usage: bash $SWEEP/bin/run_all.sh   (from ~/Sites/feedbin)
source ~/.bash_profile >/dev/null 2>&1
set -euo pipefail
SWEEP="$(cd "$(dirname "$0")/.." && pwd)"
cd ~/Sites/feedbin
ruby "$SWEEP/bin/computed_sites.rb"
echo "--- prefixes not yet reviewed (add each one to computed.tsv or to the DROP list in seed_computed.rb):"
LC_ALL=C comm -13 "$SWEEP/out/computed_reviewed.txt" <(cut -f2 "$SWEEP/out/computed_auto.tsv" | LC_ALL=C sort -u) || true
bin/rails runner "$SWEEP/bin/routes.rb"
bin/rails runner "$SWEEP/bin/views.rb"
bin/rails runner "$SWEEP/bin/mailers.rb"
ruby "$SWEEP/bin/ruby_methods.rb" helpers app/helpers app/presenters
ruby "$SWEEP/bin/ruby_methods.rb" methods app/models app/jobs lib config/initializers app/controllers app/mailers app/uploaders app/views
ruby "$SWEEP/bin/constants.rb"
ruby "$SWEEP/bin/config_keys.rb"
ruby "$SWEEP/bin/stimulus.rb"
ruby "$SWEEP/bin/coffee.rb"
bin/rails runner "$SWEEP/bin/styles.rb"
ruby "$SWEEP/bin/assets.rb"
