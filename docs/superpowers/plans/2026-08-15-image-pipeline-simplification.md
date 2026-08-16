# Image Pipeline Simplification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the advisory-lock refcount protocol that guards stored-object deletion, replacing it with a deferred best-effort sweep; fix two lost preloads that turned into N+1s; and bound the collector's batch size.

**Architecture:** The `images` table stays the source of truth for images, and rows keep being deleted when their entry is. What changes is *object* deletion: instead of being exact and immediate — which requires serialising every attach against every collect — it becomes approximate and deferred by an hour, which requires nothing. An hour is ~60× the worst-case crawl window, so an in-flight crawl can no longer lose its object, and the entire protocol built to prevent that goes away.

**Tech Stack:** Rails 8.1, Sidekiq, Fog::Storage (R2 is S3-compatible), Postgres, minitest + webmock.

**Predecessor:** the whole of `image_migration_review`. This plan edits code that branch introduced; it does not depend on anything new.

---

## Why: what the review and the scale test found

Measured against an isolated database seeded with 7,897,000 production-shaped `images` rows. No network — R2 and S3 were never contacted. Throughput via `pgbench` replaying the exact statement sequence `create_image` emits.

**The lock is not a performance problem.** `create_image` sustains 402/s on one connection and ~2,500/s on sixteen, against a target of 50/s, and the locked and unlocked variants are indistinguishable. A collector batch holding 8,000 locks across a simulated 3-second R2 round trip did not slow sixteen concurrent writers at all. Every hot query is an index scan. **None of this plan is a throughput fix.**

**The lock is a correctness problem, at batch sizes we actually produce.** `ImageGarbageCollector` takes one `pg_advisory_xact_lock` per distinct `storage_path`, all in one transaction. Measured:

| Batch | Locks in one transaction | Result |
| --- | --- | --- |
| 400 entries | 318 | ok |
| 2,000 entries | 1,586 | ok |
| 10,000 entries | 7,928 | ok, alone |
| 15,000 paths, idle server | 15,000 | `ERROR: out of shared memory` |
| 3 concurrent jobs × 3,000 | 9,000 | ok |
| 4 concurrent jobs × 3,000 | 12,000 | **2 of 4 jobs failed** |
| 6 concurrent jobs × 3,000 | 18,000 | **5 of 6 jobs failed** |

The shared lock table holds roughly `max_locks_per_transaction × (max_connections + 1)` entries **server-wide** — 6,464 at the defaults. `EntryDeleterScheduler` pushes one `EntryDeleter` per feed across every feed, so several collectors running at once is the normal case, not a spike.

The failure is fail-safe — `delete_all` is inside the same transaction, so nothing is left half-done — but the job dies, `ImageGarbageCollector` uses Sidekiq's default retry, and it burns 25 identical attempts before giving up. Those rows are then never collected. At 50 images/second rows accrue at 4.3M/day, so a collector that silently stops is the difference between a ~90 GB table and an unbounded one.

**Two read paths lost their preload** when reads moved from the `entries.image` jsonb onto associations. Both are ordinary omissions, not design problems — they are listed here because the same commit that fixes them should add the coverage that keeps them fixed.

---

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`. A single test: `bin/rails test <path> -n <name>`.
- **Establish the test baseline before starting** and record it here. It could not be captured while writing this plan: the Postgres container's IP changed and macOS then denied the `ruby` binary Local Network access, so Rails cannot reach the database. `psql` and `nc` can. Fix that first (System Settings → Privacy & Security → Local Network, or publish 5432 on the container) — no task below can be verified without it.
- **NEVER interpolate values into SQL strings** — hash conditions, bound parameters, or `sanitize_sql_array` only.
- **`Image.provider` additions are append-only. NEVER renumber.** Nothing here adds one.
- **The touch rule still governs.** An `images` row's `updated_at` may change only when the stored bytes change.
- All pipeline jobs remain `retry: false`. `ImageGarbageCollector` and `SweepStoredImages` keep Sidekiq's default retry — with the locks gone their only remaining failure mode is a transient R2 or database error, which is exactly what retry is for.
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

---

## Decisions this plan makes

**1. The sweep delay is fifteen minutes.** `Pipeline::Find` caps itself at 45 seconds and every pipeline job is `retry: false`, so the whole Find → Process → Upload chain is a couple of minutes at worst. Fifteen minutes is roughly twenty times that.

**2. `ensure_stored` goes, rather than being kept as a cheap HEAD.** It confirms the object survived between `upload_r2` and `create_image`. With the deferral the window it guards shrinks to: a fresh upload to the same `storage_path` whose `create_image` lands within milliseconds of a sweep scheduled fifteen minutes earlier for that exact path. Keeping it costs one `head_object` per upload — at 50/s that is ~130M Class B operations a month, on the order of $45, to guard a coincidence that narrow. If one ever does slip through the cost is one broken image for one entry.

**3. `Dedupe`'s post-lock existence re-check goes, and this is safe for a specific reason.** Today it re-checks, under the lock, that some row still references the path before attaching. Under the deferred sweep the row it already found *is* that reference: the sweep deletes only paths with no rows at sweep time, and by then `Dedupe` has written its own row. The interleaving the check defends against cannot be constructed any more.

**4. Row deletion does not become best-effort.** Only object deletion does. Orphaned rows are tolerable as stragglers, not as a policy — see the 4.3M/day accrual rate above.

**5. The legacy-S3 half defers too, because removing the lock is what would break it.** An earlier draft of this plan called this an optional tidy-up against a pre-existing race. That was wrong, and the correction matters: today the advisory lock is doing double duty. `ImageDeleter` is enqueued outside the lock, but the `surviving_legacy` value it acts on is computed *inside* it, and `Dedupe` cannot create a new reference without taking the same lock — so every interleaving is already safe. Remove the lock and give only the R2 half a deferral, and the legacy half is left with no protection at all:

1. `Dedupe#attach` looks up row `R` by `url_fingerprint` and reads its `storage_path` `P` and `legacy_storage_url` `L`.
2. `ImageGarbageCollector` deletes `R`, the last row referencing `P`.
3. It computes `surviving` (empty) and enqueues `ImageDeleter([L])` — **`L` is deleted now.**
4. `Dedupe` writes its new row `N`, carrying `P` and `L`.
5. Fifteen minutes later the sweep sees `N`, so the R2 object at `P` correctly survives.

`N` ends up referencing a live R2 object and a deleted legacy one. The window is `Dedupe`'s lookup-to-insert gap, a few milliseconds — but unlike the `ensure_stored` case it needs no coincidence with a scheduled job, just two concurrent operations on one path.

Whether that is visible depends on `R2_IMAGE_HOST`: `Entry#processed_image` and `#link_image` both read the R2 path first and only fall through to `legacy_storage_url` when `Image.r2_url` returns nil, which is exactly the state the branch deploys in before the read flip. So the exposure is the dual-write window — the one this branch is about to be in.

Deferring both halves closes it with the mechanism already being introduced, and makes `ImageGarbageCollector` stop knowing about stored objects entirely.

---

## Task 3 — Bound the collector batch

Lands first: it is one line, and until Task 1 lands it caps advisory locks per transaction at roughly 800 instead of unbounded.

- [ ] **`app/jobs/entry_deleter.rb`** — in `delete_entries`, replace the single enqueue with a sliced one:

```ruby
entry_ids.each_slice(1_000) { ImageGarbageCollector.perform_async(_1) }
```

  Keep it after the transaction, for the reason the existing comment gives: if the deletes roll back, the usage rows must survive too.

- [ ] **`test/jobs/entry_deleter_test.rb`** — deleting 2,500 entries enqueues 3 `ImageGarbageCollector` jobs, and the union of their args is the full id set.

- [ ] `bin/rails test test/jobs/entry_deleter_test.rb`, then commit.

---

## Task 1 — Delete the lock protocol, defer object deletion

### 1a. New job

- [ ] **Create `app/jobs/sweep_stored_images.rb`.** This is `ImageGarbageCollector#sweep` minus the lock and the transaction, plus the legacy-S3 half (decision 5), promoted to its own job so both callers — entry deletion and row replacement — share it. One query answers both survivor questions.

```ruby
# Deletes stored objects that no images row references any more, both the R2
# object at storage_path and the legacy S3 object the rows carried. Runs a
# quarter of an hour after the rows went away, which is what lets it work
# without a lock: the whole Find -> Process -> Upload chain is a couple of
# minutes at worst, so a crawl that is about to reference one of these paths
# has long since written its row.
#
# legacy_urls has to be passed in rather than re-derived: the rows that
# carried them are already gone by the time this runs.
class SweepStoredImages
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths, legacy_urls = [])
    paths = [*storage_paths].compact.uniq
    return if paths.empty?

    surviving = Image.where(storage_path: paths)
      .pluck(:storage_path, Arel.sql("data->>'legacy_storage_url'"))

    delete_r2_objects(paths - surviving.map(&:first).uniq)

    stale = [*legacy_urls].compact.uniq - surviving.filter_map(&:last)
    ImageDeleter.perform_async(stale) if stale.present?
  end

  def delete_r2_objects(paths)
    return if paths.empty?
    return if ENV["R2_BUCKET_IMAGES"].blank?

    client = Fog::Storage.new(STORAGE_R2)
    paths.each_slice(999) do |slice|
      client.delete_multiple_objects(ENV["R2_BUCKET_IMAGES"], slice, {quiet: true})
    end
    Librato.increment("image.gc_objects", by: paths.size)
  end
end
```

- [ ] **Delete `app/jobs/image_replacement_collector.rb`.** No shim. Any job already enqueued under that class name when the deploy lands will fail with `NameError` and be lost — that is one un-swept object per lost job, which is inside the tolerance for orphaned objects and not worth carrying a file for.

  `ImageCrawler::Image#create_image` is its only caller; it passes no legacy url, so the replacement path keeps the known gap the deleted file documented (a show's `itunes_image` moving to a genuinely different URL orphans a legacy S3 object). Not made worse, not fixed here.

### 1b. Remove the locks

- [ ] **`app/models/image.rb`** — delete `with_storage_lock` and `with_storage_locks` and their comments.

- [ ] **`app/models/image.rb`** — `attach!` loses the `transaction(requires_new: true)` wrapper, which existed only to savepoint a unique violation against the lock's outer transaction, and gains a retry bound. The current `retry` is unbounded:

```ruby
  # Upsert keyed by (provider, provider_id). Not create_or_find_by: the
  # find-then-save shape is what lets an existing row be updated in place
  # rather than rescued. One retry, not an open loop -- the second pass finds
  # the row the racing writer inserted and updates it.
  def self.attach!(attributes)
    attributes = attributes.symbolize_keys
    attributes[:provider_id] = attributes[:provider_id].to_s
    tries = 0
    begin
      record = find_by(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id)) ||
        new(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id))
      record.assign_attributes(attributes)
      record.save!
      record
    rescue ActiveRecord::RecordNotUnique
      raise if (tries += 1) > 1
      retry
    end
  end
```

- [ ] **`app/jobs/image_crawler/lib/image.rb`** — `create_image` drops the `::Image.with_storage_lock(storage_path) do ... end` wrapper (keep the `attach!` call and the `saved_change_to_storage_path?` branch); the replacement enqueue becomes `SweepStoredImages.perform_in(ImageGarbageCollector::SWEEP_DELAY, [replaced])`; the comment about lock keys and sorted acquisition order goes with it.

- [ ] **`app/jobs/image_crawler/lib/image.rb`** — delete `drop_image` and its comment. Nothing calls it once `resurrect` is gone.

- [ ] **`app/jobs/image_crawler/pipeline/upload.rb`** — delete `ensure_stored` and `resurrect` and their comments, and the `r2_stored = ensure_stored if r2_stored` line with the paragraph above it. `perform` keeps the existing `upload_r2` → `create_image` → `rescue` → degrade-to-legacy block unchanged.

- [ ] **`app/jobs/image_crawler/lib/dedupe.rb`** — `attach` loses the `::Image.with_storage_lock` wrapper and the `if ::Image.where(storage_path: record.storage_path).exists?` guard, so the `attach!` call is unconditional and the `return false if attached.nil?` goes. Replace the guard's comment with decision 3 above.

### 1c. Rewrite the collector

- [ ] **`app/jobs/image_garbage_collector.rb`** — no transaction, no locks, no knowledge of stored objects at all. It deletes rows and hands both object lists to the sweep. `sweep`, `orphaned_paths` and `delete_r2_objects` move to `SweepStoredImages`.

```ruby
# Removes images-table usage rows for deleted entries and hands the objects
# they referenced to the sweep. Object deletion is deferred rather than
# serialised against attachment: see
# docs/superpowers/plans/2026-08-15-image-pipeline-simplification.md.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  SWEEP_DELAY = 15.minutes

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    rows = Image.entry_owned.where(provider_id: entry_ids)
      .pluck(:id, :storage_path, Arel.sql("data->>'legacy_storage_url'"))
    return if rows.empty?

    Image.where(id: rows.map { _1[0] }).delete_all

    SweepStoredImages.perform_in(SWEEP_DELAY, rows.map { _1[1] }.uniq, rows.filter_map { _1[2] }.uniq)
    Librato.increment("image.gc_rows", by: rows.size)
  end
end
```

  The survivor subtraction that used to live here moves to `SweepStoredImages` unchanged in meaning, and its comment should move with it — it is still the thing that makes the legacy half exact under both keying schemes. Entry previews share one legacy object per `storage_path`, because `Dedupe#attach` copies `legacy_storage_url` verbatim onto every row it dedupes onto, so a surviving row carries the same value the deleted rows did and subtracting it leaves the still-referenced object alone. Content-addressed rows never go through `Dedupe`, so each carries its own per-row legacy key even when the path is shared with a surviving show or sibling episode; that key is not one any survivor references, so it is never subtracted.

  **Payload:** with Task 3's slice, worst case is ~800 paths and ~1,000 legacy URLs, around 110 KB held in Sidekiq's scheduled set for fifteen minutes. Steady-state batches are far smaller — a feed prunes roughly what it publishes — so this is the backfill ceiling, not the norm.

### 1d. Tests

**Delete** — these cover machinery that no longer exists:

- [ ] `test/models/image_test.rb` — "with_storage_lock yields inside a transaction", "with_storage_locks takes many locks in one acquisition"
- [ ] `test/jobs/image_crawler/pipeline/upload_test.rb` — `test_should_re_upload_when_the_object_vanished_before_the_row_existed`, `test_should_not_re_upload_when_the_object_is_still_there`, `test_should_keep_the_row_when_confirmation_fails_without_a_404`, `test_should_drop_the_row_and_fall_back_to_legacy_when_the_re_upload_also_fails`
- [ ] `test/jobs/image_crawler/dedupe_test.rb` — "falls back to download when GC removed the rows mid-flight". The interleaving it constructs cannot happen any more. The nil-record path stays covered by "returns false when nothing is stored for the url" directly above it.

**Move** — `test/jobs/image_replacement_collector_test.rb` becomes `test/jobs/sweep_stored_images_test.rb`, retargeted at the new class. Its three cases ("deletes an object nothing references any more", "keeps an object another row still references", "does nothing with no paths") transfer unchanged.

**Rewrite** — `test/jobs/image_garbage_collector_test.rb`. The collector no longer deletes objects or computes legacy urls, so every assertion about either belongs to the sweep now. What is left here is thin by design:

- [ ] Row-count assertions stay.
- [ ] `stub_batch_delete`/`assert_requested` and the `ImageDeleter.jobs` assertions are replaced by one assertion per case that `SweepStoredImages` was scheduled with the right paths and the right legacy urls.
- [ ] The four cases that exist to pin object-level and legacy-level refcounting — "keeps the objects while other entries reference them", "deletes orphaned objects in one batched call", "deletes the shared legacy object only with the last reference", "keeps an object shared by two different urls until the last row goes" — move wholesale into `sweep_stored_images_test.rb`, seeding rows and calling the sweep directly rather than going through the collector.
- [ ] "deletes an episode's own legacy object when a surviving show row shares its storage_path" moves too. It is the sharpest test of the subtraction rule and it now lives where the subtraction does.
- [ ] "entry_images excludes icon rows while entry_owned includes them" stays — it is about scopes, not collection.

**Add:**

- [ ] `test/jobs/sweep_stored_images_test.rb` — "leaves a path that was re-referenced after the rows were deleted". This is the behaviour the whole deferral rests on and nothing covers it today: delete the rows, create a new row on the same `storage_path`, run the sweep, assert no R2 delete was issued.
- [ ] `test/jobs/sweep_stored_images_test.rb` — the legacy counterpart, which is the race decision 5 exists to close: delete the rows, create a new row carrying the same `legacy_storage_url`, run the sweep with that url in the payload, assert `ImageDeleter` was **not** enqueued.
- [ ] `test/models/image_test.rb` — `attach!` raises rather than looping when the unique violation persists across the retry.
- [ ] `test/jobs/image_crawler/image_test.rb` — the four `ImageReplacementCollector.jobs` assertions retarget to `SweepStoredImages`, and the last one asserts the delay as well as the args.

**Invariant:**

- [ ] `grep -rn pg_advisory app/` returns nothing.

- [ ] `bin/rails test test/jobs test/models/image_test.rb`, then commit.

---

## Task 2 — Fix the two lost preloads and cover them

- [ ] **`app/controllers/api/v2/entries_controller.rb`** — add `.preload(:preview_image_record)` to both branches of `index`. `_entry_extended.json.jbuilder` reaches `preview_image_record` twice — through `entry.processed_image?` and through `entry.preview_image_data` — and nothing else in that template touches an images row, so this is the complete fix. `?mode=extended` is the documented option clients use to get images and the endpoint serves up to 100 entries, so this is 100 queries a request where `main` had none.

  Note while you are here, but do **not** fix in this commit: the non-`ids` branch has no `includes(:feed)` at all. That predates this branch.

- [ ] **`app/models/action.rb`** — add `.preload(:preview_image_record, :link_image_record)` to `results`. `Dialog::ActionResults` renders `entries/_entry` per result, and that partial calls both `entry.processed_image?` and `entry.link_image`.

- [ ] **`test/views/query_count_test.rb`** — two new cases in the existing shape: capture SQL at two collection sizes and assert the `FROM "images"` count does not grow.
  - A new `ApiEntriesQueryCountTest` bound to `Api::V2::EntriesController`, hitting `index` with `mode=extended`. It must be its own class — `ActionController::TestCase` binds one controller per class, which is why `SidebarQueryCountTest` is already separate. Reuse the existing API auth helper.
  - An action-results case rendering `Dialog::ActionResults` for an `Action` whose results contain entries with preview and link images.

- [ ] `bin/rails test test/views/query_count_test.rb test/controllers`, then commit.

---

## Verification

- [ ] Full suite green: `bundle exec rake`, compared against the baseline recorded at the top.
- [ ] `grep -rn "with_storage_lock\|ensure_stored\|resurrect\|drop_image\|pg_advisory" app/` returns nothing.
- [ ] Re-run the lock probe against a seeded database to confirm the failure is gone: four concurrent collector runs over 3,000-path batches, which previously failed two of four with `out of shared memory`.

## What this removes

Roughly 150 lines of code and 250 lines of comment, most of the latter explaining races that stop existing: `with_storage_lock`/`with_storage_locks`, `ensure_stored`, `resurrect`, `drop_image`, `attach!`'s savepoint, `Dedupe`'s post-lock re-check, `app/jobs/image_replacement_collector.rb` entirely, and the seven tests that exist only to pin their behaviour. `ImageGarbageCollector` drops to four statements and stops referring to stored objects at all.

## Deployment notes

- **`ImageReplacementCollector` jobs in flight at deploy time will fail with `NameError`.** Accepted; each one costs a single un-swept object. If that is not acceptable on the day, re-add the shim from git history for one deploy.
- **Nothing needs to be drained or ordered.** `SweepStoredImages` ships in the same deploy as its first caller, and the fifteen-minute delay means the consumer starts well after the code is live.
- **The R2 and legacy deletes both move fifteen minutes later.** Anything watching `image.gc_objects` or `entry_image.delete` will see a one-off gap of that length at deploy, then the same rates.

## Out of scope, tracked elsewhere

From the same review, not part of this plan: shrinking the row (`data` jsonb is 247 bytes/row, ~25 GB at 100M, mostly `final_url` duplicating `url` and the transitional `legacy_storage_url`); instrumenting `image.dedupe_hit` before deciding whether `index_images_on_url_fingerprint` earns its 4.4 GB; the development-only image-comparison branch in `App::EntryImageComponent`; and the `Procfile`, Elasticsearch and test-helper changes riding along on this branch.
