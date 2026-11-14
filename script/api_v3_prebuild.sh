#!/usr/bin/env bash
#
# API v3 schema, the slow parts. Builds by hand what three of the migrations
# would otherwise build inside `cap deploy`, where they would hold the deploy,
# and Sidekiq, for an hour or more. See docs/2026-11-06-api-v3-deploy.md.
#
# NOT read-only. On the database named, it:
#   - adds entries.revision and entries.edited_at
#   - builds index_entries_on_edited_at_and_id
#   - builds index_unreads_on_user_id_and_entry_created_at_and_entry_id
#   - builds index_entries_on_feed_id_and_created_at_and_id
#   - runs ANALYZE on entries and unreads
#
# The indexes are built CONCURRENTLY, so reads and writes carry on. Adding a
# column takes a brief exclusive lock on entries and rewrites no rows.
#
# Safe to run again, and after a failure: every step skips what is already
# there, and an index an interrupted build left invalid is dropped and built
# again.
#
# Run it on the database server, inside tmux or screen:
#
#   sudo -u postgres ./api_v3_prebuild.sh <database>
#
# The database is the argument, or PGDATABASE. Everything else about the
# connection comes from the usual PG* variables. MAINTENANCE_WORK_MEM=2GB
# gives the index sorts more memory than the server's default. sudo drops the
# environment, so variables go after it:
#
#   sudo -u postgres MAINTENANCE_WORK_MEM=2GB ./api_v3_prebuild.sh <database>

set -Eeuo pipefail

DATABASE="${1:-${PGDATABASE:-}}"

if [ -z "$DATABASE" ]; then
  echo "usage: $0 <database>" >&2
  exit 64
fi

# sudo drops TMUX and STY with the rest of the environment, so the processes
# above this one are checked too. /proc where there is one, ps otherwise.
process_name() {
  if [ -r "/proc/$1/comm" ]; then cat "/proc/$1/comm"; else ps -o comm= -p "$1"; fi
}

parent_of() {
  local stat
  if [ -r "/proc/$1/stat" ]; then
    # The name, in parentheses, can hold spaces; the parent is the second field after it.
    stat=$(<"/proc/$1/stat")
    stat=${stat##*) }
    set -- $stat
    echo "$2"
  else
    ps -o ppid= -p "$1" | tr -d ' '
  fi
}

in_multiplexer() {
  local pid=$$ name
  [ -n "${TMUX:-}${STY:-}" ] && return 0
  while [ "${pid:-0}" -gt 1 ]; do
    name=$(process_name "$pid" 2>/dev/null | tr '[:upper:]' '[:lower:]') || return 1
    case "$name" in *tmux*|*screen*) return 0 ;; esac
    pid=$(parent_of "$pid" 2>/dev/null) || return 1
  done
  return 1
}

if [ "${DETACHED_OK:-}" != "1" ] && ! in_multiplexer; then
  echo "Run this inside tmux or screen: the builds take an hour or more, and one that loses its connection has to start over." >&2
  echo "To run it anyway: sudo -u postgres DETACHED_OK=1 $0 $DATABASE" >&2
  exit 64
fi

# No statement timeout: a build runs for as long as it needs.
export PGOPTIONS="-c statement_timeout=0${MAINTENANCE_WORK_MEM:+ -c maintenance_work_mem=$MAINTENANCE_WORK_MEM}"

# Each -c is its own statement in one session, so a SET in the first holds for
# the second, and CREATE INDEX CONCURRENTLY is not inside a transaction.
sql() {
  psql -X -q -At -v ON_ERROR_STOP=1 -d "$DATABASE" "$@"
}

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

trap 'log "Stopped before finishing. Run it again: it picks up where it left off."' ERR

# t, f, or nothing when there is no such index.
index_valid() {
  sql -c "SELECT indisvalid FROM pg_index WHERE indexrelid = to_regclass('public.$1')"
}

column_exists() {
  [ "$(sql -c "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'entries' AND column_name = '$1'")" = "1" ]
}

# add_column <name> <definition>
#
# Waits at most 10 seconds for its lock, so a busy table makes it fail instead
# of queueing every query on entries behind it. Then it tries again.
add_column() {
  local name=$1 definition=$2 attempt output

  if column_exists "$name"; then
    log "entries.$name: already there"
    return
  fi

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    log "entries.$name: adding (attempt $attempt)"
    if output=$(sql -c "SET lock_timeout = '10s'" -c "ALTER TABLE public.entries ADD COLUMN IF NOT EXISTS $name $definition" 2>&1); then
      log "entries.$name: added"
      return
    fi
    case "$output" in
      *"lock timeout"*) sleep 5 ;;
      *) echo "$output" >&2; return 1 ;;
    esac
  done

  log "entries.$name: no lock in 10 attempts. Something is holding entries; find it and run this again."
  return 1
}

# build_index <name> <what follows ON>
#
# No lock timeout: a concurrent build waits for older transactions to finish
# without holding anyone else up.
build_index() {
  local name=$1 definition=$2 valid started

  valid=$(index_valid "$name")
  if [ "$valid" = "t" ]; then
    log "$name: already built"
    return
  fi
  if [ "$valid" = "f" ]; then
    log "$name: invalid, left by an interrupted build. Dropping it."
    sql -c "SET lock_timeout = 0" -c "DROP INDEX CONCURRENTLY IF EXISTS public.$name"
  fi

  log "$name: building"
  started=$SECONDS
  sql -c "SET lock_timeout = 0" -c "CREATE INDEX CONCURRENTLY $name ON $definition"

  if [ "$(index_valid "$name")" != "t" ]; then
    log "$name: the build returned but the index is not valid"
    return 1
  fi
  log "$name: built in $(((SECONDS - started) / 60)) min, $(sql -c "SELECT pg_size_pretty(pg_relation_size('public.$name'))")"
}

log "Database $DATABASE, $(sql -c "SELECT 'Postgres ' || current_setting('server_version')")"
sql -F '  ' -c "SELECT relname, pg_size_pretty(pg_relation_size(oid)) AS heap, reltuples::bigint || ' rows' FROM pg_class WHERE oid IN ('public.entries'::regclass, 'public.unreads'::regclass)"

waiting_on=$(sql -F '  ' -c "SELECT pid, date_trunc('second', now() - xact_start), state, left(query, 80) FROM pg_stat_activity WHERE xact_start < now() - interval '10 seconds' AND pid <> pg_backend_pid() ORDER BY xact_start")
if [ -n "$waiting_on" ]; then
  log "Transactions open for more than 10 seconds. A build waits for the ones that started before it:"
  echo "$waiting_on"
fi

add_column revision "integer NOT NULL DEFAULT 1"
add_column edited_at "timestamp(6) without time zone"

build_index index_entries_on_edited_at_and_id "public.entries (edited_at, id) WHERE edited_at IS NOT NULL"
build_index index_unreads_on_user_id_and_entry_created_at_and_entry_id "public.unreads (user_id, entry_created_at, entry_id)"
build_index index_entries_on_feed_id_and_created_at_and_id "public.entries (feed_id, created_at, id)"

log "Analyzing entries and unreads"
sql -c "ANALYZE public.entries" -c "ANALYZE public.unreads"

invalid=$(sql -c "SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid")
if [ -n "$invalid" ]; then
  log "Invalid indexes remain:"
  echo "$invalid"
  exit 1
fi

log "Done. The columns and all three indexes are in place; cap deploy will find nothing slow left to do."
