# Parallel Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Feedbin's main test suite with Rails' built-in fork-based parallel testing, isolating each worker's PostgreSQL database, Redis database, and Elasticsearch indexes, with the pg/GSSAPI fork-segfault workaround.

**Architecture:** The parent process boots once; each forked worker re-points external resources in `parallelize_setup` using ENV as the single source of truth (`REDIS_URL` gets a per-worker DB path, `TEST_WORKER` prefixes ES index names), re-running the same initializer code production uses. System tests stay serial. Spec: `docs/superpowers/specs/2026-07-09-parallel-testing-design.md`.

**Tech Stack:** Rails 8.1.3, Ruby 4.0.4, minitest 6, pg 1.6.3, redis-rb 4.8.1 (redis_cache_store), Sidekiq 8 (redis-client), Elasticsearch 8, http.rb-based `Search::Connection`.

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command that runs ruby/bundler (user requirement).
- Local services required: PostgreSQL, Elasticsearch on `localhost:9200`. Redis is spawned by test_helper on a random port.
- Full-suite command is `bundle exec rake` (default task runs `rails test`, excludes system tests).
- Serial behavior must remain byte-for-byte identical: no `TEST_WORKER` env var ⇒ index names stay `test-entries`/`test-entries-01`, Redis stays DB 0. Single-file runs (< 50 tests) do not fork.
- Commit messages: short imperative style matching repo history ("Redis config", "Update dependencies"). No AI-attribution trailers.
- `ENV["TEST_WORKER"]` is the worker-number variable name; `Search.configure!` is the ES config (re)builder. Use these names exactly everywhere.

---

### Task 1: Worker-aware `Search.index_name`

**Files:**
- Modify: `app/models/search.rb`
- Test: `test/models/search_test.rb`

**Interfaces:**
- Produces: `Search.index_name(base_name)` → `"test-<TEST_WORKER>-<base_name>"` when `ENV["TEST_WORKER"]` is set in the test env, `"test-<base_name>"` when unset, `base_name` outside test. Tasks 2 and 5 rely on exactly this.

- [ ] **Step 1: Write the failing test**

Replace the full contents of `test/models/search_test.rb` with:

```ruby
require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "prefixes the base name in the test environment" do
    with_test_worker(nil) do
      assert_equal "test-entries", Search.index_name("entries")
    end
  end

  test "includes the parallel worker number when TEST_WORKER is set" do
    with_test_worker("3") do
      assert_equal "test-3-entries", Search.index_name("entries")
    end
  end

  test "returns the base name unchanged outside the test environment" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_equal "entries", Search.index_name("entries")
    end
  end

  test "the search alias config is namespaced for the test environment" do
    prefix = ["test", ENV["TEST_WORKER"]].compact.join("-")
    assert_equal "#{prefix}-entries-01", $search[:config][:aliases][:entries]
    assert_equal "#{prefix}-actions-01", $search[:config][:aliases][:actions]
    assert_equal "#{prefix}-feeds-01", $search[:config][:aliases][:feeds]
  end

  private

  def with_test_worker(number)
    original = ENV["TEST_WORKER"]
    ENV["TEST_WORKER"] = number
    yield
  ensure
    original.nil? ? ENV.delete("TEST_WORKER") : ENV["TEST_WORKER"] = original
  end
end
```

Notes on why these shapes: the worker-format tests pin exact values deterministically by forcing `TEST_WORKER` through the helper (`ENV["X"] = nil` deletes the key in Ruby, so `with_test_worker(nil)` tests the unset path even when the suite itself later runs inside a worker). The alias-config test must compute its prefix from the ambient `ENV["TEST_WORKER"]` because `$search` is built from whatever the current process's env actually is — under Task 5 that's the worker number.

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: FAIL — `includes the parallel worker number when TEST_WORKER is set` asserts `"test-3-entries"` but gets `"test-entries"`. The other three pass.

- [ ] **Step 3: Write minimal implementation**

Replace the full contents of `app/models/search.rb` with:

```ruby
module Search
  def self.index_name(base_name)
    return base_name unless Rails.env.test?
    ["test", ENV["TEST_WORKER"], base_name].compact.join("-")
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: PASS (4 runs, 6 assertions, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/models/search.rb test/models/search_test.rb
git commit -m "Include parallel test worker number in search index names"
```

---

### Task 2: Extract `Search.configure!` so workers can rebuild `$search`

**Files:**
- Modify: `config/initializers/elasticsearch.rb`
- Test: `test/models/search_test.rb`

**Interfaces:**
- Consumes: `Search.index_name` from Task 1.
- Produces: `Search.configure!` (no args, module_function) — rebuilds the `$search` global (fresh `Search::Connection` pools under `[:servers]`, fresh `[:config][:mappings]` and `[:config][:aliases]` computed via `Search.index_name` at call time). Boot behavior unchanged: the initializer calls `Search.configure!` then `Search.setup` (non-production). Task 5's `parallelize_setup` calls both.

**Why an extraction instead of `load`-ing the initializer:** the file's body is wrapped in `Rails.application.reloader.to_prepare`, so re-`load`-ing it after boot only re-registers a callback that never fires again in the test env. A named method can be called directly post-fork.

- [ ] **Step 1: Write the failing test**

Add to `test/models/search_test.rb`, after the `"the search alias config is namespaced for the test environment"` test and before `private`:

```ruby
  test "configure! rebuilds the search config from the current environment" do
    with_test_worker("99") do
      Search.configure!
      assert_equal "test-99-entries-01", $search[:config][:aliases][:entries]
      assert_equal "test-99-actions-01", $search[:config][:aliases][:actions]
      assert_equal "test-99-feeds-01", $search[:config][:aliases][:feeds]
    end
  ensure
    Search.configure!
  end
```

(`Search.configure!` builds config and connection pools but performs no HTTP requests, so no `test-99-*` indexes are actually created. The `ensure` re-runs it to restore the ambient config for later tests.)

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'configure!' for module Search`

- [ ] **Step 3: Restructure the initializer**

In `config/initializers/elasticsearch.rb`, the current shape is:

```ruby
Rails.application.reloader.to_prepare do
  defaults = { ... }
  exact_field = { ... }
  shared_settings = { ... }
  entries_mapping = { ... }
  feeds_mapping = { ... }
  actions_mapping = { ... }

  $search = {}.tap do |hash|
    ...
  end

  module Search
    def client(mirror: false, &block)
      ...
    end
    module_function :client

    def setup
      ...
    end
    module_function :setup
  end

  unless Rails.env.production?
    Search.setup
  end
end
```

Restructure it so all the config-building locals and the `$search` assignment move inside a new `Search.configure!` module_function, and the initializer calls it once. Do not change any of the mapping/settings/servers content — move it verbatim. The resulting shape (with `...` standing for today's exact literal content):

```ruby
Rails.application.reloader.to_prepare do
  module Search
    def configure!
      exact_field = { ... }                 # moved verbatim
      shared_settings = { ... }             # moved verbatim
      entries_mapping = { ... }             # moved verbatim
      feeds_mapping = { ... }               # moved verbatim
      actions_mapping = { ... }             # moved verbatim

      $search = {}.tap do |hash|            # moved verbatim
        ...
      end
    end
    module_function :configure!

    def client(mirror: false, &block)       # unchanged
      ...
    end
    module_function :client

    def setup                                # unchanged
      ...
    end
    module_function :setup
  end

  Search.configure!

  unless Rails.env.production?
    Search.setup
  end
end
```

The trailing `ActiveSupport::Notifications.subscribe` block at the bottom of the file stays untouched.

Note: the `defaults` local (ES client logging/ssl options, currently the first thing in the `to_prepare` block) is dead code — nothing references it; the `ConnectionPool` blocks construct `Search::Connection` directly. Delete it rather than moving it. Everything else moves verbatim.

- [ ] **Step 4: Run test to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: PASS (5 runs, 0 failures)

- [ ] **Step 5: Run the search-related job tests to prove boot parity**

Run: `source ~/.bash_profile && bundle exec rails test test/jobs/search/`
Expected: PASS, same counts as on `main` (these tests exercise `Search.client`, `Search.setup`, `$search[:config]` end to end).

- [ ] **Step 6: Commit**

```bash
git add config/initializers/elasticsearch.rb test/models/search_test.rb
git commit -m "Extract Search.configure! so search config can be rebuilt"
```

---

### Task 3: Look up the SearchServerSetup connection pool at runtime

**Files:**
- Modify: `app/jobs/search/search_server_setup.rb`
- Test: `test/jobs/search/search_server_setup_test.rb` (existing coverage, no new tests)

**Interfaces:**
- Consumes: `$search[:servers]` rebuilt by `Search.configure!` (Task 2).
- Produces: `Search::SearchServerSetup#client` (instance method) returning `$search[:servers][:secondary] || $search[:servers][:primary]`. The `Client` constant is deleted; nothing outside this class references it (verified: only `perform` uses it).

**Why:** `Client = $search[...]` is evaluated at class-load time. Under CI's eager loading that happens in the parent before forking and before workers rebuild `$search`, so workers would share the parent's pool and its inherited HTTP socket.

- [ ] **Step 1: Run existing tests as the safety net**

Run: `source ~/.bash_profile && bundle exec rails test test/jobs/search/search_server_setup_test.rb`
Expected: PASS. Note the run/assertion counts.

- [ ] **Step 2: Replace the constant with a runtime lookup**

In `app/jobs/search/search_server_setup.rb`, delete line 7:

```ruby
    Client = $search[:servers][:secondary] || $search[:servers][:primary]
```

Change line 20 from:

```ruby
      Client.with { _1.bulk(records) } unless records.empty?
```

to:

```ruby
      client.with { _1.bulk(records) } unless records.empty?
```

And add a private method at the bottom of the class (after `touch_actions`):

```ruby
    private

    def client
      $search[:servers][:secondary] || $search[:servers][:primary]
    end
```

- [ ] **Step 3: Run tests to verify unchanged behavior**

Run: `source ~/.bash_profile && bundle exec rails test test/jobs/search/search_server_setup_test.rb`
Expected: PASS with the same counts as Step 1.

- [ ] **Step 4: Commit**

```bash
git add app/jobs/search/search_server_setup.rb
git commit -m "Look up search connection pool at runtime in SearchServerSetup"
```

---

### Task 4: pg fork-segfault workaround (gssencmode)

**Files:**
- Modify: `config/database.yml`

**Interfaces:**
- Produces: test connections negotiate no GSS encryption; nothing else consumes this.

**Why:** Homebrew libpq is built with GSSAPI. Its krb5 state does not survive `fork`, and forked test workers segfault (https://notes.max.engineer/ruby-pg-gem-segfault). `gssencmode: disable` keeps libpq from initializing that state. Test section only.

- [ ] **Step 1: Add gssencmode to the test section**

In `config/database.yml`, change the `test:` section to:

```yaml
test:
  adapter: postgresql
  encoding: unicode
  database: feedbin_test
  pool: <%= ENV['DB_POOL'] || 5 %>
  username: <%= ENV['POSTGRES_USERNAME'] %>
  password: <%= ENV.fetch('POSTGRES_PASSWORD', '') %>
  host: <%= ENV.fetch('POSTGRES_HOST', 'localhost') %>
  # Avoid libpq GSSAPI/krb5 state that segfaults in forked parallel-test
  # workers: https://notes.max.engineer/ruby-pg-gem-segfault
  gssencmode: disable
```

- [ ] **Step 2: Verify the option reaches the adapter**

Run: `source ~/.bash_profile && bundle exec rails runner -e test 'puts ActiveRecord::Base.connection_db_config.configuration_hash[:gssencmode]'`
Expected output: `disable`

- [ ] **Step 3: Run a DB-heavy test file to confirm connections still work**

Run: `source ~/.bash_profile && bundle exec rails test test/models/feedbin_utils_test.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add config/database.yml
git commit -m "Disable gssencmode for test database connections"
```

---

### Task 5: Parallelize the suite with per-worker Redis DBs and ES indexes

**Files:**
- Modify: `test/test_helper.rb`
- Modify: `test/application_system_test_case.rb`

**Interfaces:**
- Consumes: `Search.index_name` (Task 1), `Search.configure!` + `Search.setup` (Task 2).
- Produces: `REDIS_BASE_URL` top-level constant in test_helper (pre-fork Redis URL, no DB path); `ENV["TEST_WORKER"]` set per worker; parallelized `ActiveSupport::TestCase`; serial `ApplicationSystemTestCase`.

- [ ] **Step 1: Rework the redis spawn block in test_helper**

In `test/test_helper.rb`, replace lines 1–25 (everything from `ENV["RAILS_ENV"]` through the `$redis = {...}` block) with:

```ruby
ENV["RAILS_ENV"] ||= "test"

require "minitest"
require "minitest/mock"
require "socket"
require "uri"
require "connection_pool"

unless ENV["CI"]
  socket = Socket.new(:INET, :STREAM, 0)
  socket.bind(Addrinfo.tcp("127.0.0.1", 0))
  port = socket.local_address.ip_port
  socket.close

  ENV["REDIS_URL"] = "redis://localhost:%d" % port
  redis_test_instance = IO.popen("redis-server --port %d --save '' --appendonly no --databases 32" % port)

  redis_parent_pid = Process.pid
  Minitest.after_run do
    Process.kill("INT", redis_test_instance.pid) if Process.pid == redis_parent_pid
  end
end

REDIS_BASE_URL = URI(ENV["REDIS_URL"] || "redis://localhost:6379").tap { _1.path = "" }.to_s
```

Three changes and one deletion in there:
1. `--databases 32` — the default 16 is too tight for 12 workers plus headroom.
2. The `Process.pid` guard — `Minitest.after_run` registers an at_exit-based hook before forking; without the guard a finishing worker could kill the shared redis mid-run.
3. `REDIS_BASE_URL` — captured pre-fork; on CI (`ENV["CI"]` set, no spawned server) it falls back to the service at `localhost:6379`, stripping any DB path the URL might carry.
4. The `$redis = {entries:…, refresher:…}` block is deleted, not moved: `config/initializers/redis.rb` unconditionally reassigns `$redis` during the `require environment` five lines later, and only `$redis[:refresher]` is referenced anywhere in app or test code.

- [ ] **Step 2: Add parallelize + hooks to ActiveSupport::TestCase**

In the same file, at the top of `class ActiveSupport::TestCase`, directly after the two `include` lines and before `fixtures :all`, add:

```ruby
  parallelize(workers: :number_of_processors)

  parallelize_setup do |worker|
    ENV["TEST_WORKER"] = worker.to_s
    ENV["REDIS_URL"] = "#{REDIS_BASE_URL}/#{worker}"

    load Rails.root.join("config/initializers/redis.rb")
    Rails.cache = ActiveSupport::Cache.lookup_store(Rails.application.config.cache_store)
    Sidekiq.default_configuration.redis = {url: ENV["REDIS_URL"]}

    Search.configure!
    Search.setup
  end

  parallelize_teardown do
    $search[:config][:aliases].each_value do |index|
      Search.client { _1.delete_index(index) }
    end
  end
```

How each line isolates a resource, for review context:
- PostgreSQL needs nothing here — Rails creates `feedbin_test-<worker>` and loads schema + fixtures per worker on its own.
- `ENV["REDIS_URL"]` with a `/<worker>` path selects a per-worker Redis DB. `load`-ing the redis initializer rebuilds `$redis` from ENV (the file is already idempotent, plain top-level code). Sidekiq (redis-client) and `Rails.cache` (redis_cache_store) both construct lazily from `REDIS_URL`; the explicit `Rails.cache` rebuild and `Sidekiq.default_configuration.redis =` are insurance against anything having memoized a connection in the parent pre-fork.
- `Search.configure!` recomputes `$search` — aliases now carry the `test-<worker>-` prefix via `TEST_WORKER`, and the connection pools are fresh (the parent's boot-time `Search.setup` left used HTTP connections in the old pools; forked copies of those sockets must not be reused). `Search.setup` then creates this worker's indexes.
- The teardown deletes the worker's three physical indexes (the `[:aliases]` values are the `-01` physical index names). It only runs in parallel mode, so serial runs keep today's persist-and-reuse index lifecycle.

- [ ] **Step 3: Pin system tests to serial**

In `test/application_system_test_case.rb`, add one line directly after `driven_by :cuprite`:

```ruby
  parallelize(workers: 1)
```

(An explicit `PARALLEL_WORKERS=n` still overrides this — Rails reads the env var over the declaration — which is the intended escape hatch.)

- [ ] **Step 4: Verify serial behavior is unchanged**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: PASS, and the output must NOT contain "Running N tests in parallel" (single file is below the 50-test threshold). This proves index names stay unprefixed when no fork happens.

- [ ] **Step 5: Verify a forced parallel run with redis + search coverage**

Run: `source ~/.bash_profile && PARALLEL_WORKERS=2 bundle exec rails test test/models/search_test.rb test/models/feedbin_utils_test.rb test/models/entry_test.rb test/jobs/search/`
Expected: output contains "Running 2 tests in parallel" (wording varies: "Running N tests in parallel using 2 processes") and PASS. This exercises: worker-prefixed `$search` aliases (search_test computes from ENV), per-worker redis DBs with exact-value assertions (feedbin_utils_test, entry_test), and ES index CRUD inside workers (jobs/search).

- [ ] **Step 6: Verify worker indexes were cleaned up**

Run: `curl -s localhost:9200/_cat/indices | grep -E "test-[0-9]+-" || echo "no worker indexes"`
Expected: `no worker indexes`

- [ ] **Step 7: Commit**

```bash
git add test/test_helper.rb test/application_system_test_case.rb
git commit -m "Run tests in parallel with per-worker Redis DBs and search indexes"
```

---

### Task 6: Full-suite verification

**Files:**
- None expected; fix-forward anything the full run flushes out (flaky ordering, shared-state tests). Any fix gets its own commit.

- [ ] **Step 1: Full parallel run**

Run: `source ~/.bash_profile && bundle exec rake`
Expected: PASS, "Running N tests in parallel using 12 processes" (or the machine's core count) in the output. Runtime should drop substantially versus a serial run.

If failures appear here but not in Task 5's targeted run, they are isolation escapes. Debug with `PARALLEL_WORKERS=2` for a smaller repro; the usual suspects are tests sharing Redis keys across workers (should be impossible with per-DB isolation — check the client actually honors the URL path) or tests hardcoding `test-`-prefixed index names (grep: `grep -rn '"test-' test/`).

- [ ] **Step 2: Leftover-index check**

Run: `curl -s localhost:9200/_cat/indices | grep -E "test-[0-9]+-" || echo "no worker indexes"`
Expected: `no worker indexes`

- [ ] **Step 3: System tests still run and are serial**

Run: `source ~/.bash_profile && bundle exec rails test test/system/login_test.rb`
Expected: PASS with no "in parallel" line in the output.

- [ ] **Step 4: Commit (only if fixes were needed)**

```bash
git add -A && git commit -m "Fix test isolation issues found in full parallel run"
```
