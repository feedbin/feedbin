# Separate Elasticsearch indexes when running tests

**Date:** 2026-06-23
**Status:** Approved

## Problem

Development and test share one Elasticsearch (`ELASTICSEARCH_URL`, default
`http://localhost:9200`) **and** the same index names. Every index/alias name is
derived from `Entry.table_name` / `Action.table_name` / `Feed.table_name`, i.e.
`entries`, `actions`, `feeds` (with physical indexes `entries-01`, etc.).

The test suite's `clear_search` helper deletes those indexes between tests and
re-runs `Search.setup`. Run locally, this wipes the developer's **development**
search data. CI is unaffected today because it spins up a throwaway Elasticsearch,
but the local footgun is real.

Goal: make the test suite operate on its own indexes so teardown never touches
development (or production) data — with the smallest, simplest change.

## Approach

Prefix the search index/alias base name. The prefix is empty in dev/prod (no
change to current behavior) and `test-` under test, so the suite operates on
`test-entries`, `test-actions`, `test-feeds`.

This was chosen over running a separate Elasticsearch instance for test (via a
distinct `ELASTICSEARCH_URL`/port): prefixing requires no new infrastructure,
runs against the same single local Elasticsearch, and matches the "separate
indexes" goal. A second instance would be near-zero code but adds operational
weight (~1GB+ RAM, another service to manage locally).

## Design

### The helper

A single helper living with the other `Search::*` classes, in a new
`app/models/search.rb` — the explicit namespace file for the existing
`app/models/search/` directory:

```ruby
module Search
  def self.index_name(base_name)
    Rails.env.test? ? "test-#{base_name}" : base_name
  end
end
```

The prefix is `test-` under test and empty everywhere else, so development and
production index names are unchanged. Zeitwerk autoloads the file, so the helper
is available to the jobs, models, and the `elasticsearch.rb` initializer alike.
The initializer already references the `Search` namespace (`Search::Connection`)
while building `$search` inside its `to_prepare` block, which triggers the
autoload before the alias config calls `Search.index_name`; the initializer's
later `module Search` reopening (for `client`/`setup`) simply adds to the
already-loaded module.

### Call sites

The change is mechanical — wrap each existing index reference:
`Entry.table_name` → `Search.index_name(Entry.table_name)`. Sites:

**`config/initializers/elasticsearch.rb`**
- The 3 entries in the `aliases:` config (`"#{...table_name}-01"`)
- The 3 `add_alias(..., alias_name: ...table_name)` calls in `Search.setup`

**Jobs (`app/jobs/search/`)**
- `search_index_store.rb` — `index(...)` and `all_matches(...)` (2 sites)
- `search_index_remove.rb` — `BulkRecord` `index:`
- `actions_bulk.rb` — `all_matches(...)`
- `percolate_create.rb` — `index(...)`
- `percolate_destroy.rb` — `delete(...)`
- `reindex_feeds.rb` — `reindex(...)`
- `search_server_setup.rb` — `BulkRecord` `index:`

**Models**
- `app/models/concerns/searchable.rb` — `msearch`, `validate`, `search` (3 sites)
- `app/models/feed_search.rb` — `search(...)`

**Tests**
- `test/jobs/search/search_server_setup_test.rb:36` — queries ES by
  `Entry.table_name` directly; gets the same wrap.
- `test/test_helper.rb`'s `clear_search` already routes through the prefixed
  `$search[:config][:aliases]` hash, so it needs **no** change.

### Why nothing else moves

The physical-index suffix (`-01`), the alias machinery, and `reindex`'s
timestamped index names all derive from the same base name, so prefixing the
base flows through them automatically. There are no hardcoded `"entries"` /
`"actions"` / `"feeds"` index string literals in the codebase — every reference
goes through `Model.table_name` — so the wrap is complete.

## Testing

- Tests run **serially** (no `parallelize` in `test_helper.rb`), so a single
  static `test-` prefix is safe — there are no concurrent workers to collide on
  the shared test index.
- After the change, the existing search test suite (`test/jobs/search/*`,
  `test/models/action_test.rb`, the saved-searches controller test) should pass
  against the `test-*` indexes.
- Manual verification: run the suite locally with development search data
  present and confirm the development indexes (`entries`, `actions`, `feeds`)
  still exist and are intact afterward, while `test-*` indexes were created and
  torn down.

## Alternative considered (rejected)

Define a `Model.search_index` method on the three models instead of a free
helper, for cleaner call sites. Same edit count, but requires per-model plumbing
(`Action`/`Feed` don't include the `Searchable` concern). The single helper is
one definition covering all three uniformly, so it wins on simplicity.
