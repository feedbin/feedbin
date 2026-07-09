# Parallel Testing Design

Date: 2026-07-09
Status: Approved

## Goal

Run the Feedbin test suite with Rails' built-in parallel testing (fork-based), with full
isolation between workers for PostgreSQL, Redis, and Elasticsearch, and a workaround for
the ruby-pg fork segfault (https://notes.max.engineer/ruby-pg-gem-segfault).

## Scope

- Main suite (`ActiveSupport::TestCase` descendants) runs parallel.
- System tests (`ApplicationSystemTestCase`, cuprite/Chrome) stay serial: pinned with
  `parallelize(workers: 1)`. An explicit `PARALLEL_WORKERS=n` still overrides the pin
  (Rails behavior) — a deliberate escape hatch.
- No CI workflow changes.

## Architecture

Rails forks N workers (`:number_of_processors`, 12 locally, 4 on CI runners). The parent
boots the app once; each worker re-points its external resources in `parallelize_setup`
using `ENV` as the single source of truth, re-running the same config code production
uses. Runs below Rails' parallelization threshold (50 tests, e.g. single files) and
`PARALLEL_WORKERS=1` runs stay serial and behave exactly as today: no `TEST_WORKER` env
var, plain `test-*` index names, Redis DB 0.

### 1. Enabling (test/test_helper.rb)

```ruby
class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  parallelize_setup do |worker|
    ENV["TEST_WORKER"] = worker.to_s
    ENV["REDIS_URL"] = "#{BASE_REDIS_URL}/#{worker}"
    load Rails.root.join("config/initializers/redis.rb")
    Rails.cache = ActiveSupport::Cache.lookup_store(*Rails.application.config.cache_store)
    Search.configure!
    Search.setup
  end

  parallelize_teardown do |worker|
    # delete this worker's three physical indexes ($search[:config][:aliases] values)
  end
end
```

`BASE_REDIS_URL` is captured before fork: the spawned server URL locally, the CI service
URL (or `redis://localhost:6379` fallback) on CI, with any existing DB path stripped.

### 2. PostgreSQL

- Per-worker databases (`feedbin_test-0` … `feedbin_test-11`), schema and fixtures loaded
  per worker: handled entirely by Rails, no code.
- Segfault workaround: `gssencmode: disable` added to the **test** section of
  `config/database.yml`. Homebrew libpq is built with GSSAPI; its krb5 state does not
  survive fork and segfaults in children. Disabling GSS encryption negotiation avoids
  initializing that state. Development/production sections untouched.

### 3. Redis: per-worker DB numbers

- Worker N uses Redis database N via `REDIS_URL` path suffix (`redis://host:port/N`).
- Spawned test redis-server (test_helper, local runs only) gains `--databases 32`
  (default 16 is too tight for 12 workers plus headroom). CI's service redis keeps the
  default 16, ample for 4 workers.
- `$redis`: rebuilt by `load`-ing `config/initializers/redis.rb`, which is already
  idempotent and reads `ENV["REDIS_URL"]`.
- Sidekiq (redis-client) and `Rails.cache` (`:redis_cache_store`) build their connections
  lazily from `ENV["REDIS_URL"]`, so workers get their DB on first use. `Rails.cache` is
  rebuilt explicitly as insurance against pre-fork memoization. Implementation must
  verify nothing connects Sidekiq's pool pre-fork; if something does, reset it in
  `parallelize_setup`.
- `flush_redis` is unchanged: `flushdb` now scopes to the worker's own DB, covering
  Sidekiq, cache, and `$redis` keys alike (they share the DB).
- Cleanup: remove the vestigial pre-boot `$redis = {entries:…, refresher:…}` block in
  test_helper. The redis initializer clobbers it during environment load, and only
  `$redis[:refresher]` is used anywhere.

### 4. Elasticsearch: per-worker index names

- `Search.index_name` (app/models/search.rb) becomes worker-aware:

  ```ruby
  def self.index_name(base_name)
    return base_name unless Rails.env.test?
    ["test", ENV["TEST_WORKER"], base_name].compact.join("-")
  end
  ```

  Worker 3: alias `test-3-entries`, physical index `test-3-entries-01`. Serial runs:
  today's `test-entries` / `test-entries-01`, unchanged.
- `config/initializers/elasticsearch.rb`: the `$search = …` construction is extracted
  into `Search.configure!` (module_function, same file, still inside the `to_prepare`
  block); boot calls it exactly as today. Workers call it again post-fork, which both
  recomputes aliases with the worker prefix and replaces the connection pools — fixing
  inherited persistent HTTP sockets from the parent's boot-time `Search.setup`.
- `parallelize_teardown`: each worker deletes its three physical indexes, keeping the
  dev ES node tidy. Serial-run `test-*-01` indexes keep today's persist-and-reuse
  lifecycle.
- Collateral fixes:
  - `app/jobs/search/search_server_setup.rb:7` assigns `Client = $search[…]` at
    class-load time. Under CI eager loading that captures the parent's pool before fork
    and before `Search.configure!` replaces `$search`. Convert to a runtime lookup.
  - `test/models/search_test.rb` hardcodes `test-entries`/`test-entries-01`
    expectations, which fail under a worker prefix. Compute expected values with the
    same `TEST_WORKER` logic.

### 5. Spawned-redis lifecycle

The `Minitest.after_run` hook that kills the spawned redis-server is registered before
forking, so workers may inherit the at_exit chain. Guard the kill with the spawning
`Process.pid` so only the parent can stop the shared server.

### 6. CI

No `.github/workflows/ci.yml` changes. `bundle exec rails test` parallelizes across the
runner's cores automatically; `test:system` stays serial as before. The redis service and
single-node Elasticsearch handle per-worker DBs/indexes as-is.

## Error handling

- `Search.setup` already rescues and logs failures at boot; worker setup keeps that
  behavior (parity with serial runs — a dead ES fails tests at first search either way).
- Workers that crash leave their `feedbin_test-N` database behind; Rails reuses it on the
  next run. Leftover `test-N-*` ES indexes from a crashed worker are recreated/reused on
  the next run and deleted by the next successful teardown.

## Testing

- `bundle exec rake` (full suite, 12 workers) passes.
- `PARALLEL_WORKERS=2 bundle exec rake` passes.
- Single-file run (`bin/rails test test/models/entry_test.rb`) stays serial and passes.
- After a full run: no `test-[0-9]*` indexes remain in ES (`curl localhost:9200/_cat/indices`).
- Existing redis-value assertions (feedbin_utils_test, entry_test, entry_filter_test)
  are the isolation canary: they assert exact keys/values and fail on cross-worker bleed.
