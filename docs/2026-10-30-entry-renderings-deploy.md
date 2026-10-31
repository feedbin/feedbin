# Deploy checklist: stored entry renderings

Branch `content_formatter`. Ships the `entry_renderings` table, `Entry#rendering`, the `RenderingsRebuild` job and the `renderings:*` rake tasks.

Reads switch to the table the moment the code is live. The table starts empty, so each entry's first read after deploy renders it the way it always did and also writes a row. Every entry the crawler creates or updates is written at save time. Nothing has to run first.

## Before deploy

- [x] **Preload the rendering on the web entry endpoints.** `EntriesController#entries_by_id` (used by `show` and `preload`) preloads `:rendering_record`, so a preload batch reads its renderings in one query. API v2 preloads it through `Entry.for_api`.
- [ ] **Make `CAMO_HOST` and `CAMO_KEY` the same on every web and Sidekiq process.** Both are part of each row's checksum. If two processes disagree, each treats the other's rows as stale and re-renders and rewrites them on every read.
- [ ] **Confirm a production Sidekiq process consumes the `backfill` queue.** The repo only has `config/sidekiq-development.yml`. Rebuild jobs go to `backfill`, and nothing happens if no process listens there.
- [ ] **Check that `feedbin/html-pipeline` branch `feedbin` contains `04e2e23`.** `Gemfile.lock` pins that revision; it is pushed.
- [ ] **Merge or rebase onto main** and run `rails test`. The search tests flake under parallel load; rerun any that fail before treating them as real.

## Deploy

- [ ] **Run the migration** `20261030130000_create_entry_renderings`. It creates an empty table with a primary key and touches nothing else.
- [ ] **Deploy web and Sidekiq together.** A crawler on the old code writes no rows, and web on the new code fills them lazily, so a mixed window is harmless. It only fills more slowly.

## Right after deploy

- [ ] **Expect a short rise in render load.** The API v2 fragment cache key moved from `v2` to `v3`, so cached v2 responses are cold. The first read of each entry also writes its row, about 400 bytes. The web preload and show pages and the API v2 entry lists write a whole batch's missing rows in one insert.
- [ ] **Watch error tracking for `Entry#store_rendering` and `Entry#rendering`.** These are failures to store a rendering. Pages still render when they happen.
- [ ] **Spot-check a few pages:** an article, an edited article's diff view, a newsletter's original view, and an API v2 entry with `include_content_diff=true`.
- [ ] **Check the table is filling:**

```sql
SELECT count(*), pg_size_pretty(pg_total_relation_size('entry_renderings')) FROM entry_renderings;
```

## Later, by choice

- [ ] **A full pass is optional.** Lazy and eager filling cover everything that gets read. A full pass fills the rest in about 1.3 days with 4 processes and writes about 70 GB of WAL. Disk settles at about 60 GB at 160M entries.

```bash
rails renderings:rebuild
```

```bash
rails renderings:status
```

```bash
rails renderings:swap
```

`swap` refuses while jobs are still pending. It is safe to run again if it fails partway.

- [ ] **Re-render one feed or recent entries in place** after a change that only matters to them:

```bash
FEED=123 rails renderings:rebuild
```

```bash
SINCE=2026-10-01 rails renderings:rebuild
```

## Every future formatter change

- [ ] **Bump `ContentFormatter::VERSION`**, then record the new fingerprint. The test suite fails until you do, including for gem bumps of sanitize, nokogiri, loofah, html-pipeline, html_diff, redcarpet, addressable and zstd-ruby.

```bash
rails renderings:fingerprint
```

- [ ] **Bump the version by hand for a few uncovered inputs.** Changes to `Entry#base_url`, `Entry#fully_qualified_url`, `Entry#content_format` or `Feed#site_relative_url` are not covered by the test.
- [ ] **After a version bump, old rows re-render on first read.** Run a full pass only if you want them all current without waiting for reads.

## Rollback

- [ ] **Revert the code.** The old code never reads `entry_renderings`, so the table can stay in place.
- [ ] **Drop the table later** with a migration once you're sure:

```sql
DROP TABLE entry_renderings;
```
