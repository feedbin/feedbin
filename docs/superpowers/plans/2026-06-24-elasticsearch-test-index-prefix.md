# Separate Elasticsearch Test Indexes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the test suite operate on its own `test-`prefixed Elasticsearch indexes so test teardown never wipes development/production search data.

**Architecture:** Add one helper, `Search.index_name(base_name)`, that prepends `test-` to the index/alias base name in the test environment and is a no-op elsewhere. Route every existing index-name reference (all currently `Model.table_name`) through it. Because the physical-index suffix, alias machinery, and reindex names all derive from the same base, prefixing the base flows through everything.

**Tech Stack:** Ruby on Rails, Zeitwerk autoloading, Minitest (with `minitest/mock`), Elasticsearch 8.x via `Search::Connection` (custom HTTP client).

## Global Constraints

- Prefix value: `test-` under `Rails.env.test?`, empty string in every other environment. Development/production index names are unchanged.
- Every Elasticsearch index/alias name in the codebase derives from `Entry.table_name` / `Action.table_name` / `Feed.table_name`. Each such reference — in app code **and** test code — must be wrapped as `Search.index_name(<Model>.table_name)`. There are no hardcoded `"entries"`/`"actions"`/`"feeds"` index string literals.
- Tests run **serially** (no `parallelize` in `test_helper.rb`), so a single static prefix is safe — no concurrent workers share the test index.
- Elasticsearch must be running locally at `ELASTICSEARCH_URL` (default `http://localhost:9200`) for the search tests to pass.
- Prepend `source ~/.bash_profile` to every test command. Focused runs use `bundle exec rails test <file>`; the full-suite gate uses `bundle exec rake`.

---

### Task 1: `Search.index_name` helper

**Files:**
- Create: `app/models/search.rb`
- Test: `test/models/search_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Search.index_name(base_name) -> String`. Returns `"test-#{base_name}"` when `Rails.env.test?`, otherwise `base_name` unchanged. This is the single chokepoint Task 2 routes every index name through.

**Note on placement:** `app/models/search/` already exists as an implicit Zeitwerk namespace. Adding `app/models/search.rb` makes it an explicit namespace file — standard Zeitwerk behavior. The initializer's existing `module Search` reopening (for `client`/`setup`) continues to work; it simply adds methods to the now-explicitly-defined module.

- [ ] **Step 1: Write the failing test**

Create `test/models/search_test.rb`:

```ruby
require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "prefixes the base name in the test environment" do
    assert_equal "test-entries", Search.index_name("entries")
  end

  test "returns the base name unchanged outside the test environment" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_equal "entries", Search.index_name("entries")
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'index_name' for Search` (the `Search` namespace exists but the method does not).

- [ ] **Step 3: Write the minimal implementation**

Create `app/models/search.rb`:

```ruby
module Search
  def self.index_name(base_name)
    Rails.env.test? ? "test-#{base_name}" : base_name
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: PASS — 2 runs, 2 assertions, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/search.rb test/models/search_test.rb
git commit -m "Add Search.index_name helper for environment-namespaced indexes"
```

---

### Task 2: Route all index names through `Search.index_name`

**Files:**
- Modify: `config/initializers/elasticsearch.rb` (alias config + `Search.setup`)
- Modify: `app/jobs/search/search_index_store.rb`, `app/jobs/search/search_index_remove.rb`, `app/jobs/search/actions_bulk.rb`, `app/jobs/search/percolate_create.rb`, `app/jobs/search/percolate_destroy.rb`, `app/jobs/search/reindex_feeds.rb`, `app/jobs/search/search_server_setup.rb`
- Modify: `app/models/concerns/searchable.rb`, `app/models/feed_search.rb`
- Modify (tests): `test/jobs/search/search_server_setup_test.rb`, `test/jobs/search/search_index_store_test.rb`, `test/jobs/search/search_index_remove_test.rb`, `test/jobs/search/reindex_feeds_test.rb`
- Test: `test/models/search_test.rb` (add a sentinel)

**Interfaces:**
- Consumes: `Search.index_name(base_name) -> String` from Task 1.
- Produces: no new interface. Behavior change only — at runtime every ES index/alias name is `test-`prefixed under test.

**Why this is one atomic task:** reads and writes must agree on the index name. A partially-wired state (e.g. a job writing `entries` while a model reads `test-entries`) breaks the existing search integration tests. So all sites are wired together and verified as a unit.

- [ ] **Step 1: Add the failing sentinel test**

Append to `test/models/search_test.rb`, inside `class SearchTest`:

```ruby
  test "the search alias config is namespaced for the test environment" do
    assert_equal "test-entries-01", $search[:config][:aliases][:entries]
    assert_equal "test-actions-01", $search[:config][:aliases][:actions]
    assert_equal "test-feeds-01", $search[:config][:aliases][:feeds]
  end
```

- [ ] **Step 2: Run the sentinel to verify it fails**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb -n "/namespaced/"`
Expected: FAIL — `Expected: "test-entries-01" Actual: "entries-01"` (the initializer is not yet wired).

- [ ] **Step 3: Wire the initializer alias config**

In `config/initializers/elasticsearch.rb`, change the `aliases:` hash (currently lines ~201-203):

```ruby
      aliases: {
        entries: "#{Search.index_name(Entry.table_name)}-01",
        actions: "#{Search.index_name(Action.table_name)}-01",
        feeds: "#{Search.index_name(Feed.table_name)}-01"
      }
```

And the three `add_alias` calls in `Search.setup` (currently lines ~223-225):

```ruby
        Search.client(mirror: true) { _1.add_alias($search[:config][:aliases][:entries], alias_name: Search.index_name(Entry.table_name)) }
        Search.client(mirror: true) { _1.add_alias($search[:config][:aliases][:actions], alias_name: Search.index_name(Action.table_name)) }
        Search.client(mirror: true) { _1.add_alias($search[:config][:aliases][:feeds], alias_name: Search.index_name(Feed.table_name)) }
```

- [ ] **Step 4: Wire the search jobs**

`app/jobs/search/search_index_store.rb` — two sites:

```ruby
      Search.client(mirror: true) { _1.index(Search.index_name(Entry.table_name), id: entry.id, document: document) }
```
```ruby
      ids = Search.client { _1.all_matches(Search.index_name(Action.table_name), query: query) }
```

`app/jobs/search/search_index_remove.rb`:

```ruby
          index: Search.index_name(Entry.table_name),
```

`app/jobs/search/actions_bulk.rb`:

```ruby
      ids    = Search.client { _1.all_matches(Search.index_name(Entry.table_name), query: action.search_options) }
```

`app/jobs/search/percolate_create.rb`:

```ruby
        Search.client(mirror: true) { _1.index(Search.index_name(Action.table_name), id: @action.id, document: @action.search_body) }
```

`app/jobs/search/percolate_destroy.rb`:

```ruby
      Search.client(mirror: true) { _1.delete(Search.index_name(Action.table_name), id: action_id) }
```

`app/jobs/search/reindex_feeds.rb`:

```ruby
        client.reindex(Search.index_name(Feed.table_name), mappings: $search[:config][:mappings][:feeds]) do |new_index|
```

`app/jobs/search/search_server_setup.rb`:

```ruby
          index: Search.index_name(Entry.table_name),
```

- [ ] **Step 5: Wire the models**

`app/models/concerns/searchable.rb` — three sites:

```ruby
          responses = Search.client { _1.msearch(Search.index_name(Entry.table_name), records: records) }
```
```ruby
      result = Search.client { _1.validate(Search.index_name(Entry.table_name), query: {query: query[:query]}) }
```
```ruby
        Search.client { _1.search(Search.index_name(Entry.table_name), query: query, page: page, per_page: per_page) }
```

`app/models/feed_search.rb`:

```ruby
    response = Search.client { _1.search(Search.index_name(Feed.table_name), query: query, per_page: 3) }
```

- [ ] **Step 6: Wire the tests that query ES directly**

`test/jobs/search/search_server_setup_test.rb` (line ~36):

```ruby
      assert_equal @entries.count, Search.client { _1.search(Search.index_name(Entry.table_name), query: query) }.total
```

`test/jobs/search/search_index_store_test.rb` (line ~14):

```ruby
      entry = Search.client { _1.get(Search.index_name(Entry.table_name), id: @entry.id) }
```

`test/jobs/search/search_index_remove_test.rb` (line ~13):

```ruby
      assert_difference -> { Search.client { _1.count(Search.index_name(Entry.table_name)) } }, -@entries.count do
```

`test/jobs/search/reindex_feeds_test.rb` (lines ~13 and ~17):

```ruby
      before = Search.client {_1.get_indexes_from_alias(Search.index_name(Feed.table_name))}
```
```ruby
      after = Search.client {_1.get_indexes_from_alias(Search.index_name(Feed.table_name))}
```

- [ ] **Step 7: Verify no direct index references remain**

Run: `grep -rn "table_name" app/jobs/search app/models/concerns/searchable.rb app/models/feed_search.rb config/initializers/elasticsearch.rb test/jobs/search`
Expected: every match is inside a `Search.index_name(...)` call. If any bare `<Model>.table_name` index reference remains, wrap it.

- [ ] **Step 8: Run the sentinel — verify it passes**

Run: `source ~/.bash_profile && bundle exec rails test test/models/search_test.rb`
Expected: PASS — 3 runs, 5 assertions, 0 failures.

- [ ] **Step 9: Run the full search test suite**

Run: `source ~/.bash_profile && bundle exec rails test test/jobs/search test/models/action_test.rb test/models/search`
Expected: PASS — all green. This exercises real index→search round trips through the wired jobs and models, proving the prefixing is consistent end to end.

- [ ] **Step 10: Run the full suite as the final gate**

Run: `source ~/.bash_profile && bundle exec rake`
Expected: PASS — no regressions anywhere.

- [ ] **Step 11: Manual safety check (local only)**

With development search data present, after the suite has run, confirm the development indexes are intact and the test indexes exist separately:

```bash
curl -s "${ELASTICSEARCH_URL:-http://localhost:9200}/_cat/indices?v" | grep -E "entries|actions|feeds"
```
Expected: the unprefixed `entries-01`/`actions-01`/`feeds-01` (development data) still exist, alongside `test-entries-01`/`test-actions-01`/`test-feeds-01`.

- [ ] **Step 12: Commit**

```bash
git add config/initializers/elasticsearch.rb app/jobs/search app/models/concerns/searchable.rb app/models/feed_search.rb test/jobs/search test/models/search_test.rb
git commit -m "Use test-prefixed Elasticsearch indexes in the test environment"
```

---

## Notes

- `test/test_helper.rb`'s `clear_search` needs no change: it already routes through `$search[:config][:aliases]`, which becomes `test-*` automatically once the initializer is wired in Step 3.
- The `Search::Connection#reindex` flow builds `"#{index}-#{timestamp}"` from the name it is given, so passing it `test-feeds` (Step 4) namespaces the reindexed physical index automatically — no separate change needed.
