# Entry settings cleanup

- **Date:** 2026-10-03
- **Status:** Draft for review
- **Scope:** `entries.settings` (all rows) and `entries.data` (newsletter rows only)

## Summary

This change does four things in one backfill:

1. **It deletes the raw newsletter email source.** `settings["newsletter"]` holds a full MIME copy of every newsletter email received since 2021-05-18. No code reads it.
2. **It deletes the other unused keys:** `media_image` in `settings`, and `newsletter_text` and the Mailgun payload `newsletter` in newsletter `data`. `newsletter_to` and `newsletter_token` stay (decided 2026-10-03).
3. **It fixes the double JSON encoding of `settings`.** The column is `jsonb`, but `store ... coder: JSON` stores the hash as a JSON string inside `jsonb`. SQL cannot read its keys.
4. **It moves the sender of 2019–2021 newsletters into `settings["newsletter_from"]`.** The sender of those emails exists only in the Mailgun webhook payload, which this change deletes.

Production measurements on 2026-10-03 estimate that the cleanup frees **612.9 GiB: 491.5 GiB in `settings` and 121.4 GiB in `data`**. That is 38.1% of the `entries` table, which is 1,607.5 GiB (the 1,726 GB of the brief, in decimal units). Before compression, the raw source alone is 1,241 GiB. The backfill rewrites about 29 million rows.

The design updates rows in place: it does not use a new column. A new coder reads both formats. Two deploys switch the write format, so old processes never see a format they cannot read. A Sidekiq job converts all rows by ID range, and a Ruby path handles the rows that SQL cannot parse.

## Background

### What is stored for a newsletter today

`NewsletterReceiver#create_entry` writes these values:

| Value | Where | Content |
|---|---|---|
| `content` | column | The decoded HTML part, or the decoded text part if there is no HTML |
| `newsletter` | `settings` | `EmailNewsletter#to_s`: the whole message, encoded again by the Mail gem, attachments included |
| `newsletter_from`, `newsletter_to`, `newsletter_token` | `settings` | Sender, recipient address, address token |
| `newsletter_text` | `data` | The decoded text part |
| `type`, `format`, `newsletter_to` | `data` | `"newsletter"`, `"html"` or `"text"`, the full token |

The receiver deletes the email from object storage after it creates the entry. So `settings["newsletter"]` is the only stored copy of the email.

**The stored source is not the received email.** `Mail::Message#to_s` encodes the message again. In a dev test, a 4,799-byte message with two 8bit parts came back as 5,846 bytes, with both parts in quoted-printable and an added `Message-ID`. A DKIM signature on the stored copy can no longer verify.

### Older shapes

| Period | `data["newsletter"]` | `settings["newsletter"]` |
|---|---|---|
| 2015-11-10 to 2019-06-16 | none | none (no `settings` column) |
| 2019-06-17 to 2021-05-18 | The Mailgun webhook payload, as `{"data" => params}`: `body-html`, `body-plain`, `from`, `recipient`, `subject`, `timestamp`, the signature fields and other Mailgun keys | none |
| 2021-05-18 to now | none | The raw source |

`newsletter_text` exists in all three periods. `settings["newsletter_from"]` exists only from 2021-05-18.

### The double encoding

`settings` became a `jsonb` column on 2019-08-20, and `store :settings, ..., coder: JSON` came on the same day. Rails wraps the JSON coder, so `dump` returns a JSON string, and `jsonb` stores that string as a string scalar. On dev, all 15 rows that have `settings` are strings. The other 710 rows are NULL.

Effects:

- `settings->'newsletter'` and `settings ? 'newsletter'` return NULL or false for every string row. SQL must unwrap the value first: `(settings #>> '{}')::jsonb`.
- `Feed` had the same problem and uses `coder: JsonConverter`, which reads both formats and writes objects.
- `AccountMigration#data` and `AccountMigrationItem#data` have the same problem. They are out of scope.

### Readers

An audit of the app, feedkit, JS, the API views, search, exports, account migration, caches and the admin area found these readers:

| Value | Readers |
|---|---|
| `settings["newsletter"]` | `NewsletterUpdater` only. Nothing enqueues it, its write line is commented out, it has no `SidekiqHelper` for its `build`, and its `rescue` uses `@entry`, which is never set. |
| `data["newsletter_text"]` | None |
| `data["newsletter"]` | `EntryPresenter#newsletter_from` (`entry_presenter.rb:145`), as a fallback when `settings["newsletter_from"]` is nil. It supplies the sender line in the article header (`_article.html.erb:14-15`). |
| `settings["newsletter_from"]` | `EntryPresenter#newsletter_from`, and `ContentFormatter` (`content_formatter.rb:142`), which adds `ContentFilters::Substack` for senders at `@substack.com` |
| `data["format"]`, `data["type"]` | `Entry#content_format`, `EntryPresenter#text?`, `entry_type_class`, `NewsletterSaver`. They stay. |
| `settings["newsletter_to"]`, `settings["newsletter_token"]`, `data["newsletter_to"]` | None. `NewsletterReceiver` writes them. They stay (decision 7). |
| `settings["media_image"]` | None, and no writer. The image migration of 2026-09-09 removed the last reader. `EntryPresenter#media_image` has the same name, but it reads `itunes_image` and the feed icon. |
| `settings["archived_images"]`, `settings["embed_duration"]` | `ContentFormatter` (`archived_images?`), `Entry` and `EntryImageComponent` (`embed_duration`). They stay. |

Indirect copies:

- `Entry.entries_list` (`entry.rb:70`) selects `settings` and `data`. So every entry list reads each newsletter's raw source and `newsletter_text` from TOAST, and nothing uses them.
- `StarredEntriesController#index` caches full `Entry` objects in Redis under `"#{user.id}:starred_feed:v2"`, with no expiry. These copies include `settings` and `data`.
- `settings` is one value. So `ImageSaver`'s `update(archived_images: true)` writes the whole hash again, raw source included.

The v3 API review (`feedbin-api/docs/reviews/2026-09-26-v3-review.md`, item 10) planned to backfill `List-Unsubscribe` from the raw source. Ben decided on 2026-10-03 not to keep that option.

### Writers of `settings`

All writers use `update` or `create`, so they go through the coder:

- `NewsletterReceiver` (`newsletter_from`, `newsletter_to`, `newsletter_token`)
- `ImageSaver` (`archived_images`)
- `HarvestEmbeds`, `FeedCrawler::UpdateYoutubeVideos`, `SavePage` (`embed_duration`)

`media_image` has no writer. Old rows written from 2021-03-11 to 2026-09-09 can still contain it.

Every key that the `store` line has ever declared: `archived_images` (2019-08-20), `media_image` (2021-03-11), `newsletter` and `newsletter_from` (2021-05-18), `embed_duration` (2022-11-10), `newsletter_to` and `newsletter_token` (2025-09-25). Block 3 lists the keys that production rows actually hold, so it also finds any key that no code names.

### Retention

`EntryDeleter` keeps the newest 400 entries for each feed that has a subscriber, and 10 for a feed that has none. Starred, queued and recently played entries are never deleted, and no limit applies by age. Each newsletter feed is one sender to one address. So a row from 2019–2021 still exists only if its feed has fewer than 400 newer entries (10 without a subscriber), or if a user starred, queued or recently played it.

## Goals

1. Delete `newsletter` and `media_image` from `settings` in every row, and stop the writes.
2. Delete `newsletter` and `newsletter_text` from `data` in every newsletter row, and stop the writes.
3. Store `settings` as a `jsonb` object in every row, or as NULL when it is empty.
4. Keep the sender line on every newsletter entry, with no fallback to `data["newsletter"]`.
5. Never show an old process a format it cannot read.

## Non-goals

- A copy of `List-Unsubscribe` or other headers (decided 2026-10-03).
- A compressed copy of the raw source (see "Rejected alternatives").
- The `data` keys of non-newsletter rows. Block 3 lists them with their sizes, for a separate decision.
- The same encoding fix for `AccountMigration` and `AccountMigrationItem`.
- `newsletter_to`, `newsletter_token` and `data["newsletter_to"]` (decision 7).
- Smaller files on disk. Postgres reuses the freed space for new rows.

## Decisions

Ben confirmed these on 2026-10-03:

1. Fix the JSON encoding for all rows.
2. Copy the Mailgun-era `from` into `settings["newsletter_from"]`.
3. Delete `settings["newsletter"]`.
4. Delete `data["newsletter_text"]`.
5. Do not keep `List-Unsubscribe`.
6. Delete the other keys that nothing reads: `settings["media_image"]` and `data["newsletter"]` (the Mailgun payload).
7. Keep `settings["newsletter_to"]` and `settings["newsletter_token"]`, although nothing reads them today. This spec also keeps `data["newsletter_to"]`, which has the same name but holds the full token. A deletion cannot be undone, so the spec keeps the key until Ben says otherwise.

This spec also proposes the following. They are open for review:

8. **Update in place, not with a new column.** See "Rejected alternatives".
9. **Two deploys for the write format**, because old code raises on an object row.
10. **A permanent `EntrySettingsCoder`, not `JsonConverter`.** A `jsonb` object cannot hold a NUL character, but the old string form could. `JsonConverter` would let such a save raise.

## Evidence

### Production (2026-10-03, from the brief)

`entries`: 1,726 GB in total, TOAST 1,380 GB, heap 243 GB, indexes 60 GB, 142.4 million rows, `max_id` 5.39 billion, Postgres 11.8. Stored bytes by column, from a 0.1% block sample scaled ×1,000: `content` 590 GB, `settings` 523 GB, `data` 175 GB, `original` 37.5 GB, `summary` 27 GB.

### Production numbers (Phase 0, 2026-10-03)

Ben ran Blocks 1–3 on the production console. Each block ran on the dev database first. The blocks print key names, counts and sizes only, so no email content left production. All sizes in this section are in GiB (1024³ bytes); the brief used decimal GB.

**Block 1** (0.1% block sample, 143,080 rows, scaled ×992, 2.0 s):

| Measure | Newsletter rows | Other rows | All rows |
|---|---|---|---|
| Rows | 15.67 million (11%) | 126.3 million | 141.9 million |
| `settings` stored | 482.1 GiB | 0.9 GiB, in 12.98 million rows, all JSON strings | 483.0 GiB |
| `data` stored | 124.2 GiB | 37.3 GiB | 161.5 GiB |
| `content` stored | 300.8 GiB | not measured | not measured |

- `max_id` is 5,392,099,430, so `build` queues 53,921 jobs.
- No other row in the sample holds a `\u0000` escape.
- The backfill rewrites an estimated 28.65 million rows.

**Block 2** (0.01% block sample, 14,401 rows, scaled ×9,856, 5.1 s). "Freed" compares the stored size today with the value the backfill writes:

| Measure | Newsletter rows | Other rows | All rows |
|---|---|---|---|
| Rows the backfill rewrites | 15.95 million (all of them) | 13.53 million | 29.48 million |
| `settings`: stored, freed | 492.4 GiB, **490.9 GiB freed** | 0.9 GiB, **0.6 GiB freed** | **491.5 GiB freed** |
| `data`: stored, freed | 122.3 GiB, **121.4 GiB freed** | 40.2 GiB, nothing freed | **121.4 GiB freed** |
| **Total freed** | | | **612.9 GiB, 38.1% of the 1,607.5 GiB table** |

Uncompressed sizes of the deleted values:

| Value | Sample rows | Rows (est.) | Uncompressed |
|---|---|---|---|
| Raw source, `settings["newsletter"]` | 1,482 | 14.6 million | 1,241.1 GiB |
| `data["newsletter_text"]` | 1,618 | 15.95 million | 141.6 GiB |
| Mailgun payload, `data["newsletter"]` | 105 | 1.03 million | 125.8 GiB |
| `settings["media_image"]` | 595 | 5.86 million | 0.5 GiB |

- **All 105 Mailgun-era rows have a `from`, and none has `settings["newsletter_from"]`.** So the backfill copies the sender for about 1.03 million rows. Without the copy, all of them would lose their sender line.
- 31 sampled newsletter rows have no `settings` and no Mailgun payload. Only rows from before 2019-06-17 have that shape, so they are probably that old. They show no sender line today, and the change does not alter that.
- The sample has 0 NUL rows and 0 rows with an unexpected JSON type. The Ruby repair path stays for rows outside the sample.
- The other rows free 0.6 GiB only, for 13.5 million rewrites. Their value is the encoding fix itself.

**Block 3** (the same 0.01% sample, 4.5 s):

- `settings` holds exactly 7 keys: `newsletter`, `newsletter_from`, `media_image`, `newsletter_to`, `newsletter_token` (6.14 million rows each), `embed_duration` and `archived_images`. No key exists that the code does not name.
- `data` holds 35 keys. The two newsletter keys are the largest: `newsletter_text` (est. 61 GiB stored) and the Mailgun payload (est. 53 GiB). Block 3 estimates from average compression; Block 2's exact figure for both is 121.4 GiB.
- Of the other `data` keys, see "Follow-ups".

### Dev tests (2026-10-03)

The dev database has no newsletter entries. Each test below used seeded rows in a transaction that was rolled back, or a temporary table.

1. **Coder swap.** A coder that reads both formats read the old string rows. After a save, the row was an object, and `settings ->> 'embed_duration'` worked in SQL. A change to another column did not write `settings` again.
2. **Old code on an object row.** The current `coder: JSON` raised `TypeError: no implicit conversion of Hash into String`.
3. **Size of the object form.** For newsletter-size values, the object form was 100.2% of the string form after pglz. In the backfill test, the 19 rewritten non-newsletter rows grew by 20 bytes in total, about 1 byte per row. So the encoding fix does not save space. The deleted keys save it.
4. **NUL.** Ruby's JSON writes a NUL character as `\u0000`. Postgres rejects that escape:
   - `(settings #>> '{}')::jsonb` and `data::jsonb` raise `PG::UntranslatableCharacter`.
   - `->` and `->>` on a `json` value raise if **any** field in the value holds `\u0000`, not only the field they read.
   - `strpos` on the text of the value is safe.
   So one such row would abort a whole-range `UPDATE`.
5. **Backfill on 17 row shapes.** The tested code is the code in "Backfill job" and "`EntrySettingsCoder`". The first run gave the expected result for all 17 shapes:
   - Every deleted key was gone from object rows, string rows and NUL rows.
   - Mailgun-era rows got their `from`, and a `newsletter_from` that was already present stayed.
   - Rows with nothing left became NULL.
   - `type`, `format`, `archived_images` and `embed_duration` stayed, and `updated_at` did not change.
   A second run rewrote 0 rows (no `ctid` changed). Block 4 counted 24 string rows, 2 object rows with a deleted key and 8 newsletter data rows before the job, and 0, 0 and 0 after it.
6. **Savings arithmetic.** On the same rows, Block 2 predicted the bytes freed before the job ran. The real stored sizes after the job agreed:

   | Group | Block 2 prediction | Real result |
   |---|---|---|
   | Newsletter rows, `settings` | 157 bytes freed | 157 bytes freed |
   | Newsletter rows, `data` | 256 bytes freed | 259 bytes freed |
   | Other rows, `settings` | 20 bytes added | 20 bytes added |

   Block 2 excludes the NUL rows, so the job freed slightly more than Block 2 predicts for them.
7. **Query cache trap.** In the first version of the prototype, the second run repaired the NUL rows again. Rails 8.1's `exec_update` does not clear the query cache. Sidekiq jobs, test cases and `bin/rails runner` run inside the Rails executor, where the cache is on. So the second `select_values` returned the cached IDs. `Entry.uncached` around `perform` fixed it.

### Compression of the raw source (proxy data)

The dev database has no real newsletters. So these numbers use 658 dev entries with more than 1,000 bytes of content. Each one was wrapped in a MIME message with a text part, an HTML part, and 2,468 bytes of headers with random signature values. Then `Mail#to_s` encoded the message again, as in production. "Today" is the pglz size of the stored `settings` value, measured with `pg_column_size` in a temporary table.

| Stored form | HTML and text parts in quoted-printable | HTML and text parts in base64 |
|---|---|---|
| Today (pglz) | 100% (3,237,893 bytes) | 100% (4,642,794 bytes) |
| zstd level 3 | 74.9% | 73.0% |
| zstd level 3, `content` as dictionary | 49.6% | 72.9% |
| zstd level 3, `content` and text as dictionary | 48.7% | 72.8% |
| Headers only (pglz) | 51.9% | 36.2% |

The dictionary helps quoted-printable parts, because short runs of literal HTML match `content`. It does nothing for base64. The headers-only figure is high only because feed HTML is short. Real newsletters are longer, so their headers take a smaller share.

## Design

### `EntrySettingsCoder`

New file `app/models/entry_settings_coder.rb`, next to `json_converter.rb`. This is the deploy B version:

```ruby
# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows hold the hash as a JSON string inside jsonb. load reads both forms.
# dump writes a real object. A jsonb object cannot hold NUL, which the old
# string form could, so dump removes it. Until the backfill finishes, dump
# also drops the keys that nothing reads any more.
class EntrySettingsCoder
  DELETED_KEYS = %w[newsletter media_image].freeze

  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    value.except(*DELETED_KEYS).transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end
end
```

- **Deploy A** has the same `load`, but `dump` returns `JSON.generate(...)` of the same hash. So it still writes today's string format, and old processes can read every row.
- **Deploy C** removes `DELETED_KEYS` and the `except`, after Block 4 shows 0 rows with a deleted key.
- **`load` returns nil for a blank string.** `ActiveRecord::Store` calls `load("")` for a NULL column. `JSON.parse("")` raises, so the guard is required. The store then gives `{}`.
- **`JSON.parse`, not `JSON.load`.** `JSON.load` can create objects from `json_class` keys.
- **NUL removal is flat.** All `settings` values are strings, booleans or integers.
- **`dump` drops the deleted keys.** An app save of an old row then cannot write them back after the backfill removes them.

### `Entry`

```ruby
store :settings, accessors: [:archived_images, :newsletter_from, :embed_duration, :newsletter_to, :newsletter_token], coder: EntrySettingsCoder
```

`:newsletter` and `:media_image` leave the accessor list.

### `NewsletterReceiver` and `EmailNewsletter`

- Remove `newsletter: newsletter.to_s` from `create_entry`.
- Change `data` to `{type: "newsletter", format: newsletter.format, newsletter_to: newsletter.full_token}`.
- Delete `EmailNewsletter#to_s` and `#headers`. Nothing else calls them.
- Delete `app/jobs/newsletter_updater.rb`.

### `EntryPresenter` (deploy C)

`newsletter_from` reads `entry.newsletter_from` only. The `data.safe_dig("newsletter", "data", "from")` fallback goes.

### Starred-feed cache (deploy C)

Change the key from `starred_feed:v2` to `starred_feed:v3` in both places that use it: `StarredEntriesController#index` reads it, and `StarredEntry#expire_caches` deletes it when a star changes. If only one changes, a star change no longer clears the cached feed. New cache values then hold the clean rows. The old keys have no expiry, so they stay in Redis until Redis evicts them.

### Backfill job

New file `app/jobs/backfill_entry_settings.rb`. It follows the shape of `BackfillOriginalContent` in the original-content spec: the `utility` queue, one job for each range of 100,000 IDs, and a `build` method. `max_id` is 5.39 billion, so `build` queues about 53,900 jobs, each with about 2,600 rows.

```ruby
# Cleans entries.settings and newsletter entries.data in place: settings
# becomes a jsonb object without the keys nothing reads, the Mailgun-era
# sender moves into newsletter_from, and newsletter data loses
# newsletter_text and the Mailgun payload. One job for each range of ids:
# production ids are sparse (about 2.6% in use), so the range is larger than
# SidekiqHelper::BATCH_SIZE.
class BackfillEntrySettings
  include Sidekiq::Worker

  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000
  NUL_ESCAPE = "\\u0000"
  DELETED_SETTINGS_KEYS = %w[newsletter media_image].freeze
  DELETED_NEWSLETTER_DATA_KEYS = %w[newsletter newsletter_text].freeze

  # Newsletter rows. Each new value comes from the row itself, so if the app
  # changed the row first, Postgres computes it again from the newest
  # version. Rows with a \u0000 escape cannot be cast and are left for repair.
  NEWSLETTER_SQL = <<~SQL
    UPDATE entries
    SET settings = NULLIF(
          (COALESCE(NULLIF(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, 'null'::jsonb), '{}'::jsonb)
            - ARRAY['newsletter', 'media_image'])
          || CASE
            WHEN entries.data -> 'newsletter' -> 'data' ->> 'from' IS NULL THEN '{}'::jsonb
            WHEN COALESCE(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, '{}'::jsonb) ? 'newsletter_from' THEN '{}'::jsonb
            ELSE jsonb_build_object('newsletter_from', entries.data -> 'newsletter' -> 'data' ->> 'from')
          END,
          '{}'::jsonb),
        data = (entries.data::jsonb - ARRAY['newsletter', 'newsletter_text'])::json
    WHERE entries.id BETWEEN $1 AND $2
      AND EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3)
      AND CASE
        WHEN strpos(COALESCE(entries.settings #>> '{}', ''), $4) > 0 THEN false
        WHEN strpos(COALESCE(entries.data::text, ''), $4) > 0 THEN false
        ELSE jsonb_typeof(entries.settings) = 'string'
          OR entries.settings ?| ARRAY['newsletter', 'media_image']
          OR entries.data::jsonb ?| ARRAY['newsletter', 'newsletter_text']
      END
  SQL

  # Every other row: unwrap the JSON string into an object, without the
  # deleted keys.
  OTHER_SQL = <<~SQL
    UPDATE entries
    SET settings = NULLIF(
          NULLIF(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, 'null'::jsonb)
            - ARRAY['newsletter', 'media_image'],
          '{}'::jsonb)
    WHERE entries.id BETWEEN $1 AND $2
      AND NOT EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3)
      AND CASE
        WHEN entries.settings IS NULL THEN false
        WHEN strpos(entries.settings #>> '{}', $4) > 0 THEN false
        ELSE jsonb_typeof(entries.settings) = 'string'
          OR entries.settings ?| ARRAY['newsletter', 'media_image']
      END
  SQL

  NUL_ROWS_SQL = <<~SQL
    SELECT entries.id FROM entries
    WHERE entries.id BETWEEN $1 AND $2
      AND (
        strpos(COALESCE(entries.settings #>> '{}', ''), $4) > 0
        OR (strpos(COALESCE(entries.data::text, ''), $4) > 0
          AND EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3))
      )
  SQL

  NUL_ROW_SQL = <<~SQL
    SELECT entries.settings, entries.data, feeds.feed_type
    FROM entries LEFT JOIN feeds ON feeds.id = entries.feed_id
    WHERE entries.id = $1
    FOR UPDATE OF entries
  SQL

  def perform(batch)
    # exec_update does not clear the query cache, and Sidekiq runs jobs inside
    # the Rails executor, where the cache is on.
    Entry.uncached do
      first = (batch - 1) * BATCH_SIZE + 1
      binds = [first, first + BATCH_SIZE - 1, newsletter_type, NUL_ESCAPE]
      connection.exec_update(NEWSLETTER_SQL, "BackfillEntrySettings newsletter", binds)
      connection.exec_update(OTHER_SQL, "BackfillEntrySettings other", binds)
      connection.select_values(NUL_ROWS_SQL, "BackfillEntrySettings NUL rows", binds).each { repair(it) }
    end
  end

  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq::Client.push_bulk(
      "args" => (1..batches).each_slice(1).to_a,
      "class" => self.class
    )
  end

  private

  # Postgres cannot parse these rows, so Ruby does: it parses \u0000 into a
  # NUL character, which jsonb cannot store, so the NUL goes too.
  def repair(id)
    Entry.transaction do
      row = connection.select_one(NUL_ROW_SQL, "BackfillEntrySettings NUL row", [id])
      settings = row["settings"] && JSON.parse(row["settings"])
      settings = JSON.parse(settings) if settings.is_a?(String)
      settings = without_nul((settings || {}).except(*DELETED_SETTINGS_KEYS))
      if row["feed_type"] == newsletter_type
        data = row["data"] ? JSON.parse(row["data"]) : {}
        from = data.dig("newsletter", "data", "from")
        settings["newsletter_from"] ||= from.delete("\0") if from
        data = without_nul(data.except(*DELETED_NEWSLETTER_DATA_KEYS))
        connection.exec_update("UPDATE entries SET settings = $1::jsonb, data = $2::json WHERE id = $3", "BackfillEntrySettings repair",
          [(JSON.generate(settings) if settings.any?), JSON.generate(data), id])
      else
        connection.exec_update("UPDATE entries SET settings = $1::jsonb WHERE id = $2", "BackfillEntrySettings repair",
          [(JSON.generate(settings) if settings.any?), id])
      end
    end
  end

  def without_nul(hash)
    hash.transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end

  def newsletter_type
    Feed.feed_types.fetch("newsletter")
  end

  def connection
    Entry.connection
  end
end
```

Notes:

- **Each statement is computed from the row it changes.** It has no read-then-write step. Under READ COMMITTED, if the app changes a row after the statement starts, Postgres checks the `WHERE` again on the newest version and computes `SET` from it. So no app write is lost.
- **The NUL checks come first, inside `CASE`.** Postgres does not promise any order for `AND`. Only `CASE` guarantees that the check runs before the first `->` or cast.
- **`?|` finds deleted keys only in object rows.** Every string row matches `jsonb_typeof(settings) = 'string'` anyway.
- **Each statement lists its SQL in full.** The project rule forbids interpolation into SQL, even of constants. So the unwrap expression appears twice in `NEWSLETTER_SQL`, and the key lists appear as literals. The Ruby constants hold the same lists for the repair path.
- **Empty values become NULL.** `NULLIF(..., '{}')` stores NULL when no key is left. The store reads NULL as `{}`.
- **No callbacks, no `updated_at` change, no search reindex.** Clients do not see these entries as updated.
- **`data` is `json`.** The cast through `jsonb` changes key order and spacing. No reader depends on either.
- **The Ruby path removes NUL characters from values.** Such a value cannot exist in a `jsonb` object. Today's string form holds it only as an escape.
- **Rows that SQL fails on.** A newsletter row whose unwrapped `settings` is not an object would make `- 'newsletter'` raise `cannot delete from scalar`. The job then fails and retries, and the error shows the range. The coder always wrote a hash, so no such rows are expected.
- **Lock time.** Each statement locks the rows it changes until it ends. An app write to one of those rows waits for it.

## Rollout

### Phase 0: Measure production

Done on 2026-10-03. See "Production numbers". Blocks 1–3 stay in the appendix, so the measurement can run again before Phase 3.

### Phase 1: Deploy A

1. `EntrySettingsCoder` with the string-form `dump`, and the new `Entry` store line.
2. The receiver and `EmailNewsletter` changes.
3. Delete `NewsletterUpdater`.

After this deploy:

- Nothing writes a deleted key.
- Every process reads both formats.
- An app save of an old row already drops its deleted keys.

### Phase 2: Deploy B

When deploy A runs on every web and Sidekiq process, change `dump` to return the hash. From now on, every app write stores an object.

### Phase 3: Backfill

1. Limit the `utility` queue's concurrency.
2. In a console, run `BackfillEntrySettings.new.build`.
3. Watch replication lag, WAL volume and autovacuum on `entries` and its TOAST table.
4. When the queue is empty, run `build` again. The second run catches rows that the first run skipped and changes few or none.
5. Run Block 4 on a replica. All three counts must be 0.

### Phase 4: Deploy C

1. Remove `DELETED_KEYS` and the `except` from `EntrySettingsCoder#dump`.
2. Remove the `data.newsletter` fallback from `EntryPresenter#newsletter_from`.
3. Change the starred-feed cache key to `v3`.

### Rollback

- **Phase 1:** revert the deploy. Old code reads every row, because deploy A writes only strings.
- **Phase 2:** revert to deploy A, not to the code before it. Deploy A reads object rows; older code raises on them.
- **Phase 3 and later:** the deleted keys are gone for good. No code reads them, and this is the goal.

## Write cost and space

- **Row versions.** Each changed row gets a new heap version. The average heap row is about 1.7 KB (243 GB for 142.4 million rows). For about 29 million rows, that is about 46 GiB of heap WAL.
- **TOAST deletions.** Each newsletter row drops its old TOAST chunks: about 606 GiB of stored `settings` and `data`. At about 2 KB for each chunk, that is roughly 300 million chunk deletions. Each one writes a small WAL record, so this adds an estimate of 15 GiB.
- **Total WAL.** The estimate is at least 60 GiB, before full-page images, which can add as much again. These figures are rough.
- **Indexes.** `entries` has no fillfactor setting, so its pages are full and most updates cannot be HOT. Each update then also writes to the 3 full indexes: `entries_pkey`, the `feed_id` index with `INCLUDE`, and `public_id`. It also writes to any of the 3 partial indexes that apply to the row.
- **TOAST.** The new `settings` and `data` values of newsletter rows are small, so they stay in the heap row. The old TOAST chunks become dead, and autovacuum on the TOAST table must remove about 300 million of them. After vacuum, the TOAST table reuses their space for new values, so the table stops growing for some time. The files on disk keep their size, which is acceptable: Postgres reuses the space.
- **The object form is slightly larger for small values.** In the dev test it cost about 1 byte per row. Block 2 includes this cost in its "other" figures, so a negative "settings GB freed" there means the encoding fix costs more than `media_image` frees.
- **Data sent to Sidekiq.** The SQL statements do all the parsing in Postgres. Only the NUL rows travel to Ruby.
- **The other backfill.** The original-content backfill also rewrites rows. If the two jobs run as one, each row that needs both changes gets one new version, not two.

## Testing

Write each test before its code. Tests that call `perform` twice must pass, because of the query cache trap.

### `test/models/entry_settings_coder_test.rb` (new)

- `load` parses a JSON string, passes a hash through, and returns nil for a blank string.
- `dump` returns a hash without `newsletter` and `media_image`, and removes NUL characters from string values.
- For deploy A: `dump` returns a JSON string that the old `coder: JSON` reads.

### `test/models/entry_test.rb`

- An entry whose `settings` is a JSON string reads its accessors.
- An accessor write stores an object (`jsonb_typeof` is `object`).
- An entry with NULL `settings` reads `{}`.

### `test/jobs/newsletter_receiver_test.rb`

- A received newsletter stores no `settings["newsletter"]` and no `data["newsletter_text"]`.
- It still stores `newsletter_from`, `newsletter_to`, `newsletter_token`, `data["type"]`, `data["format"]` and `data["newsletter_to"]`.
- The `unstorable_attributes` tests use `data.newsletter_text` in hand-built hashes. Change them to a key the receiver still writes.

### `test/jobs/backfill_entry_settings_test.rb` (new)

One test for each of the 17 row shapes in the dev test:

- A 2021+ newsletter row: `settings` keeps `newsletter_from`, `newsletter_to` and `newsletter_token`, and `data` keeps `type`, `format` and `newsletter_to`.
- A Mailgun-era row with string `settings`: `newsletter_from` comes from the payload.
- A Mailgun-era row with NULL `settings`: `settings` becomes `{"newsletter_from": ...}`.
- A Mailgun-era row that already has `newsletter_from`: the value stays.
- NUL in the raw source, NUL in `newsletter_text`, and NUL in the Mailgun payload: the Ruby path repairs each one.
- A Mailgun-era row with no `from`: `settings` stays NULL.
- A newsletter object row with `media_image`: `media_image` goes, and `newsletter_to` stays.
- A non-newsletter string row becomes an object without `media_image`. A row with only `media_image`, and a string row with `{}`, become NULL.
- A non-newsletter object row with `media_image`: the key goes.
- A non-newsletter row with NUL in `settings`: the NUL goes. Its `data` does not change.
- A clean object row and a NULL row are not rewritten.
- `updated_at` does not change.
- A second `perform` changes nothing.
- `build` queues one job for each 100,000-ID range, up to `Entry.maximum(:id)`.

### `test/presenters/entry_presenter_test.rb` (deploy C)

- A newsletter entry shows the sender from `settings["newsletter_from"]`.
- An entry with only `data["newsletter"]["data"]["from"]` shows no sender line. After the backfill, no such row exists.

## Rejected alternatives

| Alternative | Why it was rejected |
|---|---|
| A new column, then a switch | It writes the same rows, plus dual writes for 6 accessors during the switch. A dropped column keeps its TOAST data until a table rewrite, so Postgres cannot reuse that space. It also needs a read switch, `ignored_columns`, a drop, and a new column name. Its rollback only protects data that nothing reads. |
| Keep the raw source, compressed with zstd | On proxy data, the best case is 48.7% of today for quoted-printable parts and 72.8% for base64. Nothing reads the source, and it is not the received email anyway. |
| Keep only the headers | No reader needs them, and `List-Unsubscribe` was the only planned use. They also hold the user's newsletter address. |
| Convert other rows only when they are next written | `entries` would hold two formats for years, and every SQL query would need to unwrap the value. Ben chose the full fix. |
| SQL only, with no Ruby path | One row with a `\u0000` escape aborts the statement for its whole range, and the job fails on every retry. |
| Ruby for every row | It sends every raw source from Postgres to Sidekiq only to delete it. |
| One deploy for the coder | Old processes raise `TypeError` on an object row while the deploy runs. |
| `JsonConverter` as the final coder | It does not remove NUL characters, so a save of such a value into a `jsonb` object raises. |

## Risks

- **The deletion is permanent.** No code reads the deleted values. This is the goal.
- **Volume.** About 29 million row versions, and an estimated 60 GiB or more of WAL. See "Write cost and space".
- **WAL and replication lag.** The backfill can write tens of millions of row versions. Limit the concurrency and watch the lag.
- **Old Substack newsletters can look different.** `ContentFilters::Substack` reads `settings["newsletter_from"]`, so Mailgun-era Substack entries get the filter for the first time. Their rendered HTML in `CacheEntryViews` stays the same until the cache entry expires.
- **The deploy order matters.** If deploy B arrives on a server before deploy A is on all of them, old processes raise. Phases 1 and 2 must be separate deploys.
- **A row whose unwrapped settings is not an object** makes its range fail. None is expected. The error names the range.

## Follow-ups (out of scope)

- **Account deletion.** `User` deletes its subscriptions, stars and queue (`user.rb:62-81`), but no association deletes feeds or entries (`feed.rb:6`). A deleted user's newsletter feed then has no subscriber, and `EntryDeleter` keeps its newest 10 entries forever. Until this project, those entries also kept the raw source. `settings/account.html.erb:58` says "All of your data will be deleted."
- **Public newsletter copies.** `NewsletterSaver` uploads each newsletter with `x-amz-acl: public-read`, and no code deletes these files.
- **The same double encoding** in `AccountMigration#data` and `AccountMigrationItem#data`.
- **`data` of other rows (37.3 GiB).** Block 3 found no large key without a reader:
  - `saved_pages` (est. 15.8 GiB), `tweet` (12.4 GiB), `itunes_summary` (1.7 GiB), `public_id_alt` (1.3 GiB), `media` (1.1 GiB), `thread` and `urls` all have readers.
  - `twitter_link_image_processed`, `itunes_image_processed` and `twitter_link_image_placeholder_color` have no reader since the image migration; only tests name them. `itunes_title`, `media_height` and `media_width` are written by feedkit and read by nothing.
  - These six keys use less than 0.2 GiB together. A rewrite of their 2–3 million rows writes more WAL than it frees, so this spec leaves them.
- **Newsletter `content` (300.8 GiB)** is about half of all `content`. It is the email itself, so nothing here deletes it, but it is the next large target for compression work.
- **`feeds.options` of 2020 newsletter feeds** holds `email_headers` and `newsletter_token`. Nothing reads `email_headers`. It is one small value per feed, so it saves little.
- **`feedbin-api`:** item 10 of the v3 review and `_objects/feed.md` (`list_unsubscribe`) assume a backfill from the raw source. That backfill is no longer possible.
- **`Entry.entries_list`** selects `settings` and `data`. After this project they are small for newsletters too, but the list partials need only `embed_duration` and `archived_images`.

## Appendix: console blocks

Each block ran on the dev database with `bin/rails runner`. Blocks 1–3 also ran on seeded rows of every shape with a 100% sample, in a transaction that was rolled back. Block 4 ran before and after the job on the same seeded rows. Every query uses bind parameters. No block prints a stored value: only key names, counts and sizes.

### Block 1: sizes by row type (production console)

```ruby
# Block 1: settings, data and content bytes, newsletter rows against all other rows.
# Reads stored sizes only (pg_column_size does not detoast), so no raw source is read.
conn = Entry.connection
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sample_percent = 0.1
newsletter_type = Feed.feed_types.fetch("newsletter")
nul_escape = "\\u0000"
reltuples = conn.select_value("SELECT reltuples::bigint FROM pg_class WHERE oid = $1::regclass", "reltuples", [Entry.table_name]).to_i
max_id = Entry.maximum(:id).to_i
row = conn.select_one(<<~SQL, "settings_sample", [sample_percent, newsletter_type, nul_escape])
  WITH sample AS (
    SELECT entries.settings, entries.data, entries.content,
      coalesce(feeds.feed_type = $2, false) AS newsletter
    FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)
    LEFT JOIN feeds ON feeds.id = entries.feed_id
  )
  SELECT
    count(*) AS sampled_rows,
    count(*) FILTER (WHERE newsletter) AS newsletter_rows,
    count(settings) FILTER (WHERE newsletter) AS newsletter_settings_rows,
    coalesce(sum(pg_column_size(settings)) FILTER (WHERE newsletter), 0) AS newsletter_settings_bytes,
    coalesce(sum(pg_column_size(data)) FILTER (WHERE newsletter), 0) AS newsletter_data_bytes,
    coalesce(sum(pg_column_size(content)) FILTER (WHERE newsletter), 0) AS newsletter_content_bytes,
    count(settings) FILTER (WHERE NOT newsletter) AS other_settings_rows,
    coalesce(sum(pg_column_size(settings)) FILTER (WHERE NOT newsletter), 0) AS other_settings_bytes,
    count(*) FILTER (WHERE CASE WHEN newsletter THEN false ELSE jsonb_typeof(settings) = 'string' END) AS other_string_rows,
    count(*) FILTER (WHERE CASE WHEN newsletter THEN false ELSE jsonb_typeof(settings) = 'object' END) AS other_object_rows,
    count(*) FILTER (WHERE CASE WHEN newsletter THEN false ELSE strpos(settings #>> '{}', $3) > 0 END) AS other_nul_rows,
    coalesce(sum(pg_column_size(settings)), 0) AS all_settings_bytes,
    coalesce(sum(pg_column_size(data)), 0) AS all_data_bytes
  FROM sample
SQL
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
sampled = row["sampled_rows"].to_i
scale = sampled.zero? ? 0 : reltuples.to_f / sampled
gb = ->(bytes) { (bytes.to_f * scale / 1024**3).round(1) }
millions = ->(count) { (count.to_f * scale / 1_000_000).round(2) }
puts "elapsed seconds: #{elapsed.round(1)}"
puts "reltuples: #{reltuples}"
puts "max_id: #{max_id}"
puts "backfill jobs at 100,000 ids each: #{(max_id / 100_000.0).ceil}"
puts "scale factor: #{scale.round(1)}"
row.each { |key, value| puts "sample #{key}: #{value}" }
puts "est. all settings GB: #{gb.(row["all_settings_bytes"])}"
puts "est. all data GB: #{gb.(row["all_data_bytes"])}"
puts "est. newsletter rows (millions): #{millions.(row["newsletter_rows"])}"
puts "est. newsletter settings GB: #{gb.(row["newsletter_settings_bytes"])}"
puts "est. newsletter data GB: #{gb.(row["newsletter_data_bytes"])}"
puts "est. newsletter content GB: #{gb.(row["newsletter_content_bytes"])}"
puts "est. other rows with settings (millions): #{millions.(row["other_settings_rows"])}"
puts "est. other settings GB: #{gb.(row["other_settings_bytes"])}"
puts "est. other rows stored as a JSON string (millions): #{millions.(row["other_string_rows"])}"
puts "est. other rows stored as an object (millions): #{millions.(row["other_object_rows"])}"
puts "est. other rows with a \\u0000 escape: #{(row["other_nul_rows"].to_f * scale).round}"
puts "est. rows the backfill rewrites (millions): #{millions.(row["newsletter_rows"].to_i + row["other_string_rows"].to_i)}"
```

### Block 2: space freed in `settings` and `data` (production console)

```ruby
# Block 2: what the cleanup frees in settings and in data. For each row in the
# 0.01% sample it computes the value the backfill writes, and compares stored
# sizes. Detoasts, so it reads the small sample only. Rows that hold a \u0000
# escape cannot be parsed in SQL; they are counted, not measured.
conn = Entry.connection
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sample_percent = 0.01
newsletter_type = Feed.feed_types.fetch("newsletter")
nul_escape = "\\u0000"
reltuples = conn.select_value("SELECT reltuples::bigint FROM pg_class WHERE oid = $1::regclass", "reltuples", [Entry.table_name]).to_i
table_bytes = conn.select_value("SELECT pg_total_relation_size($1::regclass)", "table_size", [Entry.table_name]).to_i
sampled = conn.select_value("SELECT count(*) FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)", "sample_count", [sample_percent]).to_i
groups = Entry.uncached { conn.select_all(<<~SQL, "cleanup_savings", [sample_percent, newsletter_type, nul_escape]).to_a }
  WITH sample AS (
    SELECT coalesce(feeds.feed_type = $2, false) AS newsletter, entries.settings, entries.data,
      CASE jsonb_typeof(entries.settings) WHEN 'string' THEN entries.settings #>> '{}' ELSE entries.settings::text END AS settings_text
    FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)
    LEFT JOIN feeds ON feeds.id = entries.feed_id
  ), flagged AS (
    SELECT newsletter, settings, data, settings_text,
      strpos(coalesce(settings_text, ''), $3) > 0 AS settings_nul,
      newsletter AND strpos(coalesce(data::text, ''), $3) > 0 AS data_nul
    FROM sample
  ), parsed AS (
    SELECT newsletter, settings, data, settings_nul, data_nul,
      CASE WHEN settings_nul THEN NULL ELSE settings_text::jsonb END AS settings_value,
      CASE WHEN newsletter AND NOT data_nul THEN data::jsonb END AS data_value
    FROM flagged
  ), typed AS (
    SELECT newsletter, settings, data, settings_nul, data_nul,
      CASE WHEN jsonb_typeof(settings_value) = 'object' THEN settings_value END AS settings_object,
      CASE WHEN jsonb_typeof(data_value) = 'object' THEN data_value END AS data_object,
      jsonb_typeof(settings_value) NOT IN ('object', 'null') AS settings_odd,
      jsonb_typeof(data_value) <> 'object' AS data_odd
    FROM parsed
  ), cleaned AS (
    SELECT newsletter, settings, data, settings_object, data_object, settings_nul, data_nul, settings_odd, data_odd,
      NOT (settings_nul OR data_nul OR coalesce(settings_odd, false) OR coalesce(data_odd, false)) AS measured,
      NULLIF(
        (COALESCE(settings_object, '{}'::jsonb) - ARRAY['newsletter', 'media_image'])
        || CASE
          WHEN data_object -> 'newsletter' -> 'data' ->> 'from' IS NULL THEN '{}'::jsonb
          WHEN settings_object ? 'newsletter_from' THEN '{}'::jsonb
          ELSE jsonb_build_object('newsletter_from', data_object -> 'newsletter' -> 'data' ->> 'from')
        END,
        '{}'::jsonb) AS settings_after,
      CASE WHEN data_object IS NULL THEN data ELSE (data_object - ARRAY['newsletter', 'newsletter_text'])::json END AS data_after
    FROM typed
  )
  SELECT newsletter,
    count(*) AS rows,
    count(*) FILTER (WHERE settings_nul OR data_nul) AS nul_rows,
    count(*) FILTER (WHERE settings_odd OR data_odd) AS odd_rows,
    count(*) FILTER (WHERE measured AND (jsonb_typeof(settings) = 'string'
      OR settings_object ?| ARRAY['newsletter', 'media_image']
      OR data_object ?| ARRAY['newsletter', 'newsletter_text'])) AS rows_rewritten,
    coalesce(sum(pg_column_size(settings)), 0) AS settings_stored_bytes,
    coalesce(sum(pg_column_size(settings)) FILTER (WHERE measured), 0) AS settings_before_bytes,
    coalesce(sum(pg_column_size(settings_after)) FILTER (WHERE measured), 0) AS settings_after_bytes,
    coalesce(sum(pg_column_size(data)), 0) AS data_stored_bytes,
    coalesce(sum(pg_column_size(data)) FILTER (WHERE measured), 0) AS data_before_bytes,
    coalesce(sum(pg_column_size(data_after)) FILTER (WHERE measured), 0) AS data_after_bytes,
    count(*) FILTER (WHERE settings_object ? 'newsletter') AS raw_source_rows,
    coalesce(sum(octet_length(settings_object ->> 'newsletter')), 0) AS raw_source_uncompressed_bytes,
    count(*) FILTER (WHERE settings_object ? 'media_image') AS media_image_rows,
    coalesce(sum(octet_length(settings_object ->> 'media_image')), 0) AS media_image_uncompressed_bytes,
    count(*) FILTER (WHERE data_object ? 'newsletter_text') AS newsletter_text_rows,
    coalesce(sum(octet_length(data_object ->> 'newsletter_text')), 0) AS newsletter_text_uncompressed_bytes,
    count(*) FILTER (WHERE data_object ? 'newsletter') AS mailgun_rows,
    coalesce(sum(octet_length((data_object -> 'newsletter')::text)), 0) AS mailgun_uncompressed_bytes,
    count(*) FILTER (WHERE data_object -> 'newsletter' -> 'data' ->> 'from' IS NOT NULL) AS mailgun_from_rows,
    count(*) FILTER (WHERE data_object ? 'newsletter' AND settings_object ? 'newsletter_from') AS mailgun_rows_with_settings_from
  FROM cleaned
  GROUP BY newsletter
  ORDER BY newsletter
SQL
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
scale = sampled.zero? ? 0 : reltuples.to_f / sampled
gb = ->(bytes) { (bytes.to_f * scale / 1024**3).round(1) }
millions = ->(count) { (count.to_f * scale / 1_000_000).round(2) }
total_settings_freed = 0
total_data_freed = 0
puts "elapsed seconds: #{elapsed.round(1)}"
puts "sampled rows (all feeds): #{sampled}"
puts "scale factor: #{scale.round(1)}"
groups.each do |row|
  group = row["newsletter"] ? "newsletter" : "other"
  settings_freed = row["settings_before_bytes"].to_i - row["settings_after_bytes"].to_i
  data_freed = row["data_before_bytes"].to_i - row["data_after_bytes"].to_i
  total_settings_freed += settings_freed
  total_data_freed += data_freed
  row.except("newsletter").each { |key, value| puts "#{group} sample #{key}: #{value}" }
  puts "#{group} est. rows (millions): #{millions.(row["rows"])}"
  puts "#{group} est. rows the backfill rewrites (millions): #{millions.(row["rows_rewritten"])}"
  puts "#{group} est. rows left to the Ruby repair path: #{(row["nul_rows"].to_f * scale).round}"
  puts "#{group} est. settings stored GB: #{gb.(row["settings_stored_bytes"])}"
  puts "#{group} est. settings GB freed: #{gb.(settings_freed)}"
  puts "#{group} est. data stored GB: #{gb.(row["data_stored_bytes"])}"
  puts "#{group} est. data GB freed: #{gb.(data_freed)}"
  puts "#{group} raw source uncompressed GB: #{gb.(row["raw_source_uncompressed_bytes"])}"
  puts "#{group} media_image uncompressed GB: #{gb.(row["media_image_uncompressed_bytes"])}"
  puts "#{group} newsletter_text uncompressed GB: #{gb.(row["newsletter_text_uncompressed_bytes"])}"
  puts "#{group} Mailgun payload uncompressed GB: #{gb.(row["mailgun_uncompressed_bytes"])}"
end
puts "est. settings GB freed, all rows: #{gb.(total_settings_freed)}"
puts "est. data GB freed, all rows: #{gb.(total_data_freed)}"
puts "est. total GB freed: #{gb.(total_settings_freed + total_data_freed)}"
puts "entries table GB now (heap, TOAST and indexes): #{(table_bytes.to_f / 1024**3).round(1)}"
puts "est. share of the entries table freed, %: #{table_bytes.zero? ? 0 : (100.0 * (total_settings_freed + total_data_freed) * scale / table_bytes).round(1)}"
```

### Block 3: every key in `settings` and `data`, with the GB each would free (production console)

```ruby
# Block 3: every top-level key in settings and data, with row counts, value sizes
# and the GB a deletion of that key would free. Prints key names and sizes only,
# never values. Detoasts, so it reads the 0.01% sample. The per-key GB applies the
# column's stored/uncompressed ratio for that row group, so it is an estimate:
# values under about 2 KB are stored uncompressed, larger ones compressed.
conn = Entry.connection
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sample_percent = 0.01
newsletter_type = Feed.feed_types.fetch("newsletter")
nul_escape = "\\u0000"
reltuples = conn.select_value("SELECT reltuples::bigint FROM pg_class WHERE oid = $1::regclass", "reltuples", [Entry.table_name]).to_i
sampled = conn.select_value("SELECT count(*) FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)", "sample_count", [sample_percent]).to_i
scale = sampled.zero? ? 0 : reltuples.to_f / sampled
totals = Entry.uncached { conn.select_all(<<~SQL, "column_totals", [sample_percent, newsletter_type, nul_escape]).to_a }
  SELECT coalesce(feeds.feed_type = $2, false) AS newsletter,
    count(*) AS rows,
    count(entries.settings) AS settings_rows,
    coalesce(sum(pg_column_size(entries.settings)), 0) AS settings_stored_bytes,
    coalesce(sum(octet_length(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN entries.settings #>> '{}' ELSE entries.settings::text END)), 0) AS settings_text_bytes,
    count(*) FILTER (WHERE strpos(COALESCE(entries.settings #>> '{}', ''), $3) > 0) AS settings_nul_rows,
    count(entries.data) AS data_rows,
    coalesce(sum(pg_column_size(entries.data)), 0) AS data_stored_bytes,
    coalesce(sum(octet_length(entries.data::text)), 0) AS data_text_bytes,
    count(*) FILTER (WHERE strpos(COALESCE(entries.data::text, ''), $3) > 0) AS data_nul_rows
  FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)
  LEFT JOIN feeds ON feeds.id = entries.feed_id
  GROUP BY 1
  ORDER BY 1
SQL
settings_keys = Entry.uncached { conn.select_all(<<~SQL, "settings_keys", [sample_percent, newsletter_type, nul_escape]).to_a }
  WITH sample AS (
    SELECT coalesce(feeds.feed_type = $2, false) AS newsletter,
      CASE jsonb_typeof(entries.settings) WHEN 'string' THEN entries.settings #>> '{}' ELSE entries.settings::text END AS settings_text
    FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)
    LEFT JOIN feeds ON feeds.id = entries.feed_id
    WHERE entries.settings IS NOT NULL
  ), parsed AS (
    SELECT newsletter, CASE WHEN strpos(settings_text, $3) > 0 THEN NULL ELSE settings_text::jsonb END AS settings_object
    FROM sample
  )
  SELECT newsletter, pair.key, count(*) AS rows, sum(octet_length(pair.value::text)) AS value_bytes
  FROM parsed, jsonb_each(CASE WHEN jsonb_typeof(settings_object) = 'object' THEN settings_object ELSE '{}'::jsonb END) AS pair
  GROUP BY newsletter, pair.key
  ORDER BY value_bytes DESC
SQL
data_keys = Entry.uncached { conn.select_all(<<~SQL, "data_keys", [sample_percent, newsletter_type, nul_escape]).to_a }
  WITH sample AS (
    SELECT coalesce(feeds.feed_type = $2, false) AS newsletter, entries.data::text AS data_text
    FROM entries TABLESAMPLE SYSTEM ($1) REPEATABLE (42)
    LEFT JOIN feeds ON feeds.id = entries.feed_id
    WHERE entries.data IS NOT NULL
  ), parsed AS (
    SELECT newsletter, CASE WHEN strpos(data_text, $3) > 0 THEN NULL ELSE data_text::jsonb END AS data_object
    FROM sample
  )
  SELECT newsletter, pair.key, count(*) AS rows, sum(octet_length(pair.value::text)) AS value_bytes
  FROM parsed, jsonb_each(CASE WHEN jsonb_typeof(data_object) = 'object' THEN data_object ELSE '{}'::jsonb END) AS pair
  GROUP BY newsletter, pair.key
  ORDER BY value_bytes DESC
SQL
gb = ->(bytes) { (bytes.to_f * scale / 1024**3).round(2) }
puts "elapsed seconds: #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)}"
puts "sampled rows (all feeds): #{sampled}"
puts "scale factor: #{scale.round(1)}"
totals.each do |row|
  group = row["newsletter"] ? "newsletter" : "other"
  row.except("newsletter").each { |key, value| puts "#{group} #{key}: #{value}" }
  puts "#{group} settings stored/uncompressed: #{row["settings_text_bytes"].to_i.zero? ? 0 : (row["settings_stored_bytes"].to_f / row["settings_text_bytes"].to_f).round(3)}"
  puts "#{group} data stored/uncompressed: #{row["data_text_bytes"].to_i.zero? ? 0 : (row["data_stored_bytes"].to_f / row["data_text_bytes"].to_f).round(3)}"
end
ratio = {}
totals.each do |row|
  group = row["newsletter"] ? "newsletter" : "other"
  ratio[["settings", group]] = row["settings_text_bytes"].to_i.zero? ? 1.0 : row["settings_stored_bytes"].to_f / row["settings_text_bytes"].to_f
  ratio[["data", group]] = row["data_text_bytes"].to_i.zero? ? 1.0 : row["data_stored_bytes"].to_f / row["data_text_bytes"].to_f
end
{"settings" => settings_keys, "data" => data_keys}.each do |column, keys|
  puts "#{column} distinct keys: #{keys.size}"
  keys.first(80).each do |row|
    group = row["newsletter"] ? "newsletter" : "other"
    freed = row["value_bytes"].to_f * ratio.fetch([column, group], 1.0)
    puts "#{column} #{group} key=#{row["key"]} rows=#{row["rows"]} est_rows_millions=#{(row["rows"].to_f * scale / 1_000_000).round(2)} value_bytes=#{row["value_bytes"]} est_uncompressed_gb=#{gb.(row["value_bytes"])} est_gb_freed_if_deleted=#{gb.(freed)}"
  end
end
```

### Block 4: rows still to fix (replica console, after Phase 3)

```ruby
# Block 4: rows the backfill has not fixed yet. Reads every row, so run it on a replica.
conn = Entry.connection
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
newsletter_type = Feed.feed_types.fetch("newsletter")
nul_escape = "\\u0000"
# uncached: a second run of this block in the same session must read the table again.
row = Entry.uncached { conn.select_one(<<~SQL, "settings_remaining", [newsletter_type, nul_escape]) }
  SELECT
    count(*) FILTER (WHERE jsonb_typeof(entries.settings) = 'string') AS string_rows,
    count(*) FILTER (WHERE jsonb_typeof(entries.settings) = 'object'
      AND entries.settings ?| ARRAY['newsletter', 'media_image']) AS deleted_settings_key_rows,
    count(*) FILTER (WHERE feeds.feed_type = $1 AND CASE
      WHEN strpos(COALESCE(entries.data::text, ''), $2) > 0 THEN true
      ELSE entries.data::jsonb ?| ARRAY['newsletter', 'newsletter_text']
    END) AS deleted_data_key_rows
  FROM entries
  LEFT JOIN feeds ON feeds.id = entries.feed_id
SQL
puts "elapsed seconds: #{(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)}"
puts "rows still stored as a JSON string: #{row["string_rows"]}"
puts "object rows still holding a deleted settings key: #{row["deleted_settings_key_rows"]}"
puts "newsletter rows still holding a deleted data key (or a NUL escape): #{row["deleted_data_key_rows"]}"
```
