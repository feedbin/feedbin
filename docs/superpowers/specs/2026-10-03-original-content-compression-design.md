# Compressed original content

- **Date:** 2026-10-03
- **Status:** Draft for review
- **Scope:** `entries.original` and `Entry#content_diff` only

## Summary

Replace the `entries.original` JSON column with a `bytea` column, `compressed_original_content`. The new column holds only the first version of the content. zstd compresses it, and the entry's current content is the zstd dictionary. In production, about 9.8 million rows (6.9%) have an `original`, and it uses an estimated 37.5 GB, which is 2.2% of the 1,726 GB `entries` table. On 4,681 real Daring Fireball rows, the new value is 3.1% of today's size, so the expected saving is about 36 GB. Reads are faster than today, and `content_diff` output does not change. API v2 keeps the same `original` key and shape. It builds the hash from the entry's own columns plus the decompressed original content.

## Background

### How `original` works today

- `FeedCrawler::EntryUpdate` (`app/jobs/feed_crawler/lib/entry_update.rb`) writes `original` one time only. This occurs at the first significant change to an entry that `published_recently?` accepts. A significant change adds more than 50 characters of text.
- `original` is a JSON hash with 8 fields: `author`, `content`, `title`, `url`, `entry_id`, `published`, `data`, and `fingerprint`.
- Later updates do not change `original`. Each entry keeps one old version, the first one.

### Readers

| Reader | Where | What it uses |
|---|---|---|
| `Entry#content_diff` | Web article view ("View changes since original"), API v2 with `include_content_diff=true` | `original["content"]` only |
| API v2 `original` key | `_entry_extended.json.jbuilder` (always), `_entry_default.json.jbuilder` (with `include_original=true`) | The full hash |

No other code reads `original`. The diff is the only feature that needs it, and the diff needs only the content.

## Goals

1. Keep only what `content_diff` needs: the first version of the content.
2. Reduce the storage for that value to about 1–3% of today's size.
3. Keep the `content_diff` output the same.
4. Keep the API v2 `original` key with the same 8 keys, in the same order, with the same value formats.
5. Add no measurable cost to reads.

## Non-goals

- A history of every version.
- A history of the title, author, URL, or other fields.
- A cache of formatted content. That is a separate project.
- Changes to API v3. The design document in `feedbin-api` needs a follow-up edit (see "Follow-ups").

## Evidence

### Production numbers (2026-10-03)

Ben ran read-only console blocks on production. Each block ran on the dev database first.

**The `entries` table (catalog sizes):**

| Part | Size | Share |
|---|---|---|
| Whole table | 1,726 GB | 100% |
| TOAST | 1,380 GB | 80% |
| Heap | 243 GB | 14% |
| Indexes | 60 GB | 3% |
| Other (TOAST index, free-space map, visibility map) | 44 GB | 3% |

The table has 142.4 million rows, but `max_id` is 5.39 billion, so only 2.6% of IDs are in use. This affects the backfill batch size.

**Stored bytes by column**, from a 0.1% block sample of 143,044 rows, multiplied by 1,000:

| Column | Estimated total |
|---|---|
| `content` | 590 GB |
| `settings` | 523 GB |
| `data` | 175 GB |
| `original` | 37.5 GB |
| `summary` | 27 GB |
| All other measured columns | 48 GB |

**Rows with an `original`**, from the same sample:

| Measure | Result |
|---|---|
| Rows with an `original` | 9,833 of 143,048 (6.9%), or about 9.8 million in the table |
| Stored size per `original` | average 3,812 B, median 2,207 B, p90 8,171 B, p99 21,747 B, max 554,800 B |
| Concentration | No feed dominates. The 10 feeds with the most `original` bytes hold 5.8% of them. |
| Growth | Rows created in 2025 hold about 2.7 GB of `original`. Rows created in 2026 up to October 3 hold about 3.4 GB. |

The growth figures count only rows that still exist, because old entries get deleted.

**Feed 47 (Daring Fireball):** 26,378 rows. 4,681 of them (17.7%) have an `original`. `original` uses 9,138,114 bytes on disk, or an average of 1,952 bytes per row. The feed has originals in every year from 2013 to 2026.

**Feed 47 real pairs.** These come from a dump of all 4,681 rows with an `original`. The values are raw database values, so the API formatter problem of the first sample does not apply. Every value rebuilt the original exactly.

| Measure | Result |
|---|---|
| New size, stored (incl. CRC and Postgres header) | 283,002 bytes, which is 3.1% of today's 9,138,114 |
| New value size | average 61 B, median 30 B, p90 80 B, p99 333 B, max 12,354 B |
| Compress, all rows | 35 ms (7.4 µs each) |
| Decompress with CRC check, all rows | 12 ms (2.5 µs each) |

- **The largest value** is 12,354 bytes. Its original is 28.5 KB, but its current content is only 112 bytes, so the dictionary cannot help. Such outliers raise the average above the first sample's 1.5%.
- **5 rows have blank current content.** `compress` returns `nil` for them. These rows cannot show a diff today either, because `content_diff` needs `content`.
- **67 originals are identical to the current content, and 50 more have the same length.** `content_diff` shows nothing for these 117 rows today, and that does not change.

### First sample: `entries.json`

These numbers come from `entries.json`, a sample file that is not in the repo. It holds 100 Daring Fireball entries from API v2, and 21 of them have an `original`. The API formats `content` but sends `original` raw. To compare like with like, each original went through `ContentFormatter.api_format` first. The raw pairs in the database should give the same sizes or smaller. Phase 0 checks this.

#### Size

Postgres TOAST compression (pglz on Postgres 11) already compresses `original`. The "today" figure is the size on disk, measured with `pg_column_size` in a temporary table on the dev database.

| What is stored | Bytes for 21 entries | vs today |
|---|---|---|
| `original` JSON today (after pglz) | 85,410 | 100% |
| zstd, no dictionary, content only | 52,763 | 62% |
| zstd, shared trained dictionary (best case) | 39,943 | 47% |
| Zlib with the current content as the dictionary | 33,454 | 39% |
| **zstd level 3 with the current content as the dictionary, plus the 4-byte CRC** | **~1,310** | **~1.5%** |

The last row adds the Postgres header (1 byte for each value under 127 bytes) to the measured 1,280 bytes. The largest value is 242 bytes. The other zstd rows used level 19.

#### Speed

These times come from benchmark-ips on an Apple Silicon Mac, with 100 entries that all have an original.

| Operation | 100 entries | Per entry |
|---|---|---|
| Read today: `JSON.parse` of `original` | 235 µs | 2.3 µs |
| Read new: CRC32 check + zstd decompress | 160 µs | 1.6 µs |
| Write new: zstd level 3 | 0.87 ms | 9 µs |
| `content_diff` HTMLDiff step (for comparison) | 157 ms | 1.6 ms |

The largest entry (58 KB) takes 6 µs to read and less than 2.3 ms to write.

#### Stale-base test

zstd does not check that the dictionary is the same one used to compress. Each value was decompressed with a dictionary that had one changed character. 15 of the 21 values gave wrong text with no error. This is why the design stores a CRC32 of the dictionary.

## Design

### Storage

- **New column:** `entries.compressed_original_content`, type `bytea`, nullable, no default.
- **Byte layout:**
  - Bytes 0–3: CRC32 of the current `content` bytes, big-endian (`pack("N")`).
  - Bytes 4 and after: one zstd frame of the original content at level 3. The dictionary is the current `content`.
- **NULL** means the entry has no original.

zstd output is already compressed, so Postgres TOAST compression has nothing to gain from it. Most values are under 100 bytes and stay inline in the row.

### `OriginalContent` module

New file: `app/models/original_content.rb`. It has two functions and no state.

```ruby
# The first version of an entry's content, compressed with zstd. The entry's
# current content is the dictionary, so the value is tiny, but only that exact
# content can read it back. The first 4 bytes are a CRC32 of that content, so
# a stale value reads as nil, never as wrong text.
module OriginalContent
  def self.compress(original, base:)
    return nil if original.blank? || base.blank?
    [Zlib.crc32(base)].pack("N") + Zstd.compress(original, level: 3, dict: base)
  end

  def self.decompress(blob, base:)
    return nil if blob.nil? || base.blank?
    return nil unless blob.unpack1("N") == Zlib.crc32(base)
    Zstd.decompress(blob.byteslice(4..), dict: base).force_encoding(Encoding::UTF_8)
  rescue RuntimeError => exception
    ErrorService.notify(
      error_class: "OriginalContent#decompress",
      error_message: "zstd decompress failed",
      parameters: {exception: exception}
    )
    nil
  end
end
```

- `compress` returns `nil` when either input is blank. A blank base cannot work as a dictionary, and a blank original has nothing to diff.
- `decompress` returns `nil` for a missing value, a blank base, or a CRC mismatch. These are normal cases, so it does not report them.
- A zstd error after a CRC match means the stored data is damaged. `decompress` reports it and returns `nil`. zstd-ruby raises `RuntimeError` for these failures.
- zstd detects only damage to the frame's structure. The frame has no checksum, so a changed byte inside the compressed text gives wrong text with no error. This is the same as for any text column.

### `Entry`

```ruby
# Deploy 1 stops loading the legacy column. The backfill still reads it by
# name. Deploy 2 drops the column and removes this line.
self.ignored_columns += ["original"]

before_save :recompress_original_content

def original_content
  OriginalContent.decompress(compressed_original_content, base: content)
end

private

# A stored value only decompresses against the content it was made from, so
# every content change must re-encode it. Skip when this save also sets the
# column: the caller already made it against the new content.
def recompress_original_content
  return unless will_save_change_to_content? && compressed_original_content?
  return if will_save_change_to_compressed_original_content?
  original = OriginalContent.decompress(compressed_original_content, base: content_in_database)
  self.compressed_original_content = OriginalContent.compress(original, base: content)
end
```

- **Why a model callback:** `EntryUpdate`, `SavePage`, `HarvestLinks`, and `Entry#update_content` all write `content`. A callback covers every writer that saves through Active Record.
- **Writers that skip callbacks:** a search for `update_all`, `update_columns`, and `upsert` on `content` finds none. If one appears later, the stored value goes stale and the reader returns `nil`. The result is a missing diff, not a wrong one.
- **The second guard is required.** Without it, the callback would check the new value from `EntryUpdate` against the old content, fail the CRC, and set the column to `nil`.
- **If the original cannot be read**, `compress(nil, ...)` returns `nil`, and the callback clears the column.
- **Why deploy 1 ignores `original`:** `partial_inserts` is `false` in this app, so every INSERT names all the columns its process knows about. Deploy 2 can drop the column safely only if the running code already ignores it. A check on the dev database confirmed that, with the column ignored, a query can still select it by name, get a parsed hash, and clear it with `update_all`. `update_columns` raises `ActiveModel::MissingAttributeError` for an ignored column, and `update_all` accepts a JSON string but not a hash.
- **No legacy fallback:** `original_content` reads only the new column. Until the backfill converts an entry, that entry shows no diff, and its API v2 `original` is `null`. The backfill converts the newest ID ranges first to keep this short for the entries people read.

`Entry#content_diff` reads `original_content` in place of `original["content"]`. The rest of the method stays the same:

```ruby
def content_diff
  @content_diff ||= begin
    result = nil
    original = original_content
    if content && original.present? && original.length != content.length
      begin
        before = ContentFormatter.format!(original, self)
        after = ContentFormatter.format!(content, self)
        result = HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{after}</div>").inline_html
        result = result.html_safe
      rescue
      end
    end
    result
  end
end
```

### `FeedCrawler::EntryUpdate`

Replace the 8-field hash with one value:

```ruby
if significant_change?(current_content, new_content) && @original_entry.published_recently?
  create_update_notifications(@original_entry)
  if @original_entry.original_content.nil?
    update["compressed_original_content"] = OriginalContent.compress(current_content, base: new_content)
  end
  Librato.increment("entry.change", source: "large")
else
  Librato.increment("entry.change", source: "small")
end
```

- `current_content` is the content before this update, so it becomes the original.
- `new_content` is the content after this update, so it is the dictionary.
- `original_content.nil?` keeps today's rule that only the first significant change sets the original. A stale value also reads as `nil`, so the next significant change can start a new original.
- **Entries the backfill has not converted yet:** `original_content` is `nil` for them, so a significant change writes a temporary original, which is the content before that update. The backfill later replaces it with the legacy value, which is the true first version.

### API v2

The public API does not change. The `original` key keeps its 8 keys in the same order. `content` comes from `original_content`. The other 7 values come from the entry's own columns, not from the `original` column.

New method in `EntryPresenter`:

```ruby
# API v2 keeps the shape of the old original hash. Only content is the
# first version. The other fields are the entry's current values.
def api_original
  original = entry.original_content
  return nil if original.nil?
  {
    author: entry.author,
    content: original,
    title: entry.title,
    url: entry.url,
    entry_id: entry.entry_id,
    published: entry.published,
    data: entry.data,
    fingerprint: entry.fingerprint
  }
end
```

Both jbuilder templates change from `json.original entry.original` to `json.original entry_presenter.api_original`. In `_entry_default.json.jbuilder`, the line stays inside the `include_original` condition.

- **When no original exists,** the value is `null`, as today.
- **Value formats stay the same.** Jbuilder encodes the columns in the same formats as the stored JSON. A check on the dev database confirmed that `published` encodes as `2026-10-03T13:24:23.000Z`, the same format as the stored values. `fingerprint` is a UUID string, `data` is a hash, and `entry_id` is a string.
- **One value meaning changes.** Today, the 7 fields other than `content` hold the values from the time of the first significant change. After this change, they hold the current values. In the 4,681 feed 47 rows, the stored value differs from the current column as follows:

  | Field | Rows that differ |
  |---|---|
  | `title` | 470 (10.0%) |
  | `fingerprint` | 975 (20.8%) |
  | `url` | 76 (1.6%) |
  | `published` | 35 (0.7%) |
  | `data` | 6 (0.1%) |
  | `author`, `entry_id` | 0 |
- **The legacy column is not used.** The method reads only `original_content` and the current columns, so it works the same in every rollout phase.

### Dependency

Add `gem "zstd-ruby"` to the `Gemfile`. It is a native gem that includes libzstd, so it needs no system library. The tests used version 2.0.10.

## Backfill

New job: `app/jobs/backfill_original_content.rb`. It follows the shape of `BackfillProviderIds`: the `utility` queue, one job for each range of IDs, and a `build` method that queues all ranges.

It does not use `SidekiqHelper::BATCH_SIZE` (5,000) or `build_ids`. Only 2.6% of IDs are in use, so 5,000-ID batches would queue 1,078,413 jobs, and most would find no rows. The job uses its own range of 100,000 IDs. That makes 53,921 jobs, which read an average of about 2,600 rows each. In production, the read query took 0.01 s for a 5,000-ID range. About 9.8 million rows have an `original`, so the backfill makes about 9.8 million single-row UPDATEs.

```ruby
# Moves each legacy original value into compressed_original_content and
# clears the legacy column. One job for each range of ids: production ids are sparse
# (about 2.6% in use), so the range is larger than SidekiqHelper::BATCH_SIZE.
# Entry ignores the original column, so this job selects it by name.
#
# Each build is a pass. Two Redis counters track it, because a full-table
# count of the legacy rows cannot finish under production's statement
# timeout: a pass is done when no jobs are pending, and a done pass that
# found no legacy rows proves the backfill is complete.
class BackfillOriginalContent
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000
  PENDING_KEY = "backfill_original_content:pending"
  FOUND_KEY = "backfill_original_content:found"
  COUNTER_TTL = 30.days.to_i

  def self.progress
    pending, found = Sidekiq.redis { |redis| [redis.get(PENDING_KEY), redis.get(FOUND_KEY)] }
    {pending: pending.to_i, found: found.to_i}
  end

  def perform(batch)
    first = (batch - 1) * BATCH_SIZE + 1
    found = 0
    Entry.where(id: first..(first + BATCH_SIZE - 1)).where.not(original: nil)
      .select(:id, :content, :original, :updated_at)
      .find_each(batch_size: 500) do |entry|
        convert(entry)
        found += 1
      end
    Sidekiq.redis do |redis|
      redis.incrby(FOUND_KEY, found)
      redis.decr(PENDING_KEY)
    end
  end

  # The updated_at condition skips a row the crawler changed after the read.
  # That row keeps its legacy original, and the next pass converts it. The
  # legacy value replaces any temporary original EntryUpdate wrote meanwhile.
  # update_all skips callbacks and leaves updated_at as it is.
  def convert(entry)
    compressed = OriginalContent.compress(entry.original&.dig("content"), base: entry.content)
    Entry.where(id: entry.id, updated_at: entry.updated_at)
      .update_all(compressed_original_content: compressed, original: nil)
  end

  # Starts a pass: resets both counters, then queues every range, newest
  # first, because recently updated entries are the ones people read.
  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq.redis do |redis|
      redis.set(PENDING_KEY, batches)
      redis.set(FOUND_KEY, 0)
      redis.expire(PENDING_KEY, COUNTER_TTL)
      redis.expire(FOUND_KEY, COUNTER_TTL)
    end
    Sidekiq::Client.push_bulk(
      "args" => batches.downto(1).map { [it] },
      "class" => self.class
    )
  end
end
```

- **The job selects the ignored `original` column by name.** Normal queries do not load it after deploy 1, but an explicit `select` returns it as a parsed hash, and `update_all` can clear it.
- **One `UPDATE` per row** writes the new value and clears `original` together. Space in the TOAST table becomes free for reuse as the job runs.
- **A temporary original gets replaced.** If `EntryUpdate` wrote a temporary original for an unconverted entry, `convert` replaces it with the legacy value, which is the true first version.
- **Each `UPDATE` also writes a new version of the heap row and its WAL.** The average heap row is about 1.7 KB. Until vacuum runs, the old version is dead space.
- **The `updated_at` condition protects against a race.** If the crawler changes the row after the job reads it, the `UPDATE` matches no row and writes nothing. That row keeps its legacy `original`, and the next pass converts it.
- **`update_all` skips callbacks and leaves `updated_at` unchanged.** The value is already made against the current content. Clients do not see these entries as updated.
- **Rows with a blank original or blank content** get `NULL` in both columns.
- **Two Redis counters track each pass.** `build` starts a pass and resets them. Each job adds the legacy rows it found and marks itself finished. A full-table count of the legacy rows cannot replace this, because production connections have a 15-second `statement_timeout`, and the `utility` queue holds other jobs, so its size cannot show when the backfill is done. A finished pass that found 0 legacy rows proves the backfill is complete.

## Rollout

### Phase 0: Measure production

Done on 2026-10-03. See "Production numbers" under "Evidence".

The rollout takes two deploys, with the backfill between them.

### Phase 1: Deploy 1

1. Add the gem.
2. Migration: `add_column :entries, :compressed_original_content, :binary`. On Postgres 11 this is instant, because the column has no default.
3. Deploy the `OriginalContent` module, the `Entry` changes (with `ignored_columns` for `original` and no fallback), the `EntryUpdate` change, the API v2 change, and the backfill job.

After this deploy, nothing reads or writes `original` except the backfill job. Until the backfill converts an entry, that entry shows no diff.

### Phase 2: Backfill

1. In a console, run `BackfillOriginalContent.new.build`. It queues the newest ID ranges first.
2. Read `BackfillOriginalContent.progress`. When `pending` is 0, the pass is done.
3. If the done pass shows `found` more than 0, run `build` again and repeat step 2. A pass that finds 0 legacy rows proves the backfill is complete. The first pass finds about 9.8 million rows, and the next pass converts the rows that the crawler changed during the first one.

### Phase 3: Deploy 2

1. Migration: `safety_assured { remove_column :entries, :original, :json }`. Deploy 1 already ignores the column, so the running code does not use it when the migration runs.
2. Remove `self.ignored_columns += ["original"]` from `Entry`. The migration runs before the new code starts, so the new code never sees the column.
3. Delete the backfill job and its test.
4. Deploy.

Deploy 2 is cleanup only. It can go out with any later deploy after phase 2 shows 0 legacy rows.

Postgres reuses the space that phases 2 and 3 free. The files on disk do not get smaller, and shrinking them is out of scope.

### Rollback

- **After deploy 1, before the backfill:** old code reads `original` again and ignores the new column. Entries that got a new original after deploy 1 show no diff with old code, and their API v2 `original` is `null`. No data is lost.
- **After the backfill:** the stored values of the 7 fields other than `content` are deleted for good. This is the goal of the project. The original content stays available in the new column, and API v2 fills the other 7 fields from the current columns. Old code would show no diff for converted entries.

## Testing

Write each test before its code.

### `test/models/original_content_test.rb` (new)

- A round trip with UTF-8 text gives back the same string with UTF-8 encoding.
- A round trip with content larger than 32 KB works.
- A round trip works when the current content is much shorter than the original, so the dictionary does not help. Feed 47 has a row with a 28.5 KB original and 112 bytes of current content.
- `decompress` with a changed base returns `nil`.
- `decompress` with a `nil` value returns `nil`.
- `compress` with a blank original or a blank base returns `nil`.
- `decompress` with damaged zstd data and a correct CRC returns `nil` and reports to `ErrorService`.

### `test/models/entry_test.rb`

- `original_content` reads the new column.
- `Entry` does not load the `original` column. Remove this test in deploy 2.
- After two later content changes, `original_content` still returns the first version.
- Content changed with `update_columns` makes `original_content` and `content_diff` return `nil`.
- Content changed to an empty string clears the stored value.
- A save that sets `compressed_original_content` and `content` together keeps the new value.
- A save that does not change `content` does not change the stored value.
- `content_diff` gives the same HTML as today for the same original and current content.

### `test/jobs/feed_crawler/receiver_test.rb`

- Change "should not create original nil content" to check `compressed_original_content`.

### `test/jobs/feed_crawler/entry_update_test.rb` (new)

- The first significant change stores the old content as the original.
- A second significant change keeps the first original.
- A small change keeps the original.
- A small change to an entry without an original stores nothing.
- A significant change to an entry older than 7 days stores nothing.
- A significant change to an unconverted entry writes a temporary original and leaves the legacy column alone. Remove this test in deploy 2.

### `test/controllers/api/v2/entries_controller_test.rb`

- With `include_original=true`, `original` has the 8 keys `author`, `content`, `title`, `url`, `entry_id`, `published`, `data`, and `fingerprint`, in that order.
- `original.content` is the first version of the content.
- The other 7 values are equal to the entry's current columns.
- `original.published` uses the format `YYYY-MM-DDTHH:MM:SS.sssZ`.
- `original` is `null` for an entry without one.
- The extended template returns the same `original` value.

### `test/system/article_test.rb`

- The "diff" test sets `original: {content: ...}`. Change it to set the new column.

### `test/jobs/backfill_original_content_test.rb` (new)

- The job converts `original["content"]` into the new column and sets `original` to `NULL`.
- The job leaves a row alone when its `updated_at` changed after the read.
- The job sets both columns to `NULL` for a row with a blank original.
- The job sets both columns to `NULL` for a row with blank current content.
- The job replaces a temporary original with the legacy value.
- `build` resets the pass counters.
- `perform` counts its finished job and the legacy rows it found.
- A pass after the conversion finds 0 legacy rows.
- A second run over the same range changes nothing.
- `build` queues one job for each 100,000-ID range, up to `Entry.maximum(:id)`, newest range first.
- The job does not change `updated_at`.

Tests write the ignored legacy column with `update_all(original: hash.to_json)` and read it with `pick(:original)`.

## Decisions

Ben confirmed these on 2026-10-03.

1. **zstd, not Zlib.** zstd adds a native gem. Ruby's built-in Zlib also supports a dictionary and needs no gem, but its 32 KB window limit gives 39% of today's size instead of 1.5–3.1%. Long posts hold most of the bytes.
2. **The public API stays the same.** API v2 `original` keeps all 8 keys. It builds them from the entry's current columns and `original_content`, not from the `original` column, which deploy 2 removes.
3. **Column name:** `compressed_original_content`.
4. **Old originals do not expire.** At about 60 bytes each, keeping them costs little.
5. **Two deploys.** Deploy 1 adds the column and ignores `original`, with no legacy fallback. Deploy 2 drops `original`. Unconverted entries show no diff while the backfill runs, and the backfill converts the newest ID ranges first.

## Rejected alternatives

| Alternative | Why it was rejected |
|---|---|
| Text diffs: line, word, or prefix/suffix trim | Sizes are for the 21 entries, before Postgres compression. A line diff gave 29,003 bytes, and it fails for feeds with all their HTML on one line. A word diff gave 2,971 bytes, but it took 21 s for one 58 KB post. A trim gave 96,349 bytes, because it fails when the author edits more than one place. |
| A shared trained zstd dictionary | 47–54% of today. It also needs a dictionary file that must be kept forever. |
| zstd with no dictionary | 62% of today. |
| Base64 in the existing JSON column | About a third larger than `bytea`, and the old 8-field shape stays in the schema. |
| A diff from the previous version to the latest one | It changes the feature from "changes since original" to "changes since last update". The storage cost is the same. |
| Postgres compression only (pglz, or lz4 in Postgres 14+) | TOAST compresses each value on its own and cannot use the overlap between `original` and `content`. lz4 gave 88,096 bytes against 85,410 for pglz. |

## Risks

- **The size ratio comes from one feed.** The 3.1% ratio comes from 4,681 Daring Fireball rows. Other feeds can differ, but the saving is close to 36 GB unless the ratio is much worse, because the new values are small either way.
- **The saving is small next to the table.** About 36 GB is 2.1% of the 1,726 GB table. `settings` (523 GB) and `data` (175 GB) are much larger. See "Follow-ups".
- **The backfill writes a new heap row version for each converted row.** This adds WAL and dead tuples, and the heap file can grow for a time. See "Backfill".
- **The gem must build on deploy.** `zstd-ruby` compiles a native extension.
- **Diffs are missing for unconverted entries while the backfill runs.** API v2 `original` is `null` for them in that time. The newest ID ranges convert first.
- **Writers that skip callbacks** would make values stale. None exist today, and the CRC turns a stale value into a missing diff.
- **API v2 `original` values:** the 7 fields other than `content` now show current values, not the values at the time of the first significant change. A client that compares `original.title` with `title` no longer sees a difference.

## Follow-ups (out of scope)

- `feedbin-api/_objects/entry.md` (the v3 design) calls `original` "the pre-edit snapshot" of title, author, content, and URL. After this change, only `content` is from before the edit. Update that description, or reduce `original` to content in v3.
- A cache of formatted content with the same zstd method (separate design).
- **`settings` uses an estimated 523 GB, 30% of the table.** For newsletter entries, `settings["newsletter"]` holds the full raw email source (`newsletter.to_s` in `NewsletterReceiver`). The only reader is `NewsletterUpdater`, and its write line is commented out. `NewsletterSaver` and the newsletter page build from `content`. This is likely the largest disk saving available, so it needs its own investigation.
