# Entry Settings Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the raw newsletter email source and the other unread keys from `entries.settings` and newsletter `entries.data`, store `settings` as a real `jsonb` object, and move the Mailgun-era sender into `settings["newsletter_from"]`.

**Architecture:** `NewsletterReceiver` stops writing the raw source and `newsletter_text`. A new `EntrySettingsCoder` reads both the old JSON-string form and the object form, and drops the deleted keys and NUL characters on every write. Deploy A writes the old string form, so old processes can still read every row. Deploy B writes objects and ships `BackfillEntrySettings`, a Sidekiq job that converts every row by ID range in SQL, with a Ruby path for rows SQL cannot parse. Deploy C removes the presenter fallback and the backfill.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, Postgres 11 (production and dev), Minitest, Sidekiq (fake mode in tests), WebMock.

**Spec:** `docs/superpowers/specs/2026-10-03-entry-settings-cleanup-design.md`

## Global Constraints

- Deleted keys: `settings["newsletter"]` and `settings["media_image"]` in every row; `data["newsletter"]` (the Mailgun payload) and `data["newsletter_text"]` in newsletter rows.
- Kept keys: `settings` `archived_images`, `embed_duration`, `newsletter_from`, `newsletter_to`, `newsletter_token`; newsletter `data` `type`, `format`, `newsletter_to`. Never delete these.
- A row's sender comes from `data["newsletter"]["data"]["from"]` only when `settings["newsletter_from"]` is absent.
- Empty `settings` after the cleanup is stored as SQL `NULL`, never `{}`.
- Backfill: queue `utility`, `BATCH_SIZE = 100_000`, one job for each ID range, ranges in ascending order. Every change happens in SQL computed from the row itself, inside `Entry.uncached`. `updated_at` never changes.
- Never interpolate values or identifiers into SQL. Use bind parameters (`$1`, `$2`, ...) with `exec_update`, `select_value`, `select_values` and `select_one`.
- Deploy order: Deploy A (Tasks 1–2). Deploy B (Tasks 3–4), only after Deploy A runs on every web and Sidekiq process. The backfill, after Deploy B. Deploy C (Task 5), only after a pass ends with `pending: 0, changed: 0, repaired: 0` in `BackfillEntrySettings.progress`.
- The Postgres 19 upgrade and smaller files on disk are out of scope. Do not mention them in code, comments or commits.
- Work on the branch `entry-settings-cleanup`, created from `main`, in the worktree `.worktrees/entry-settings-cleanup`. The main checkout at `~/Sites/feedbin` belongs to another session on the branch `original-content-compression`. Do not change, stash or check out anything there.
- That branch also changes `app/models/entry.rb` and `test/models/entry_test.rb`. When both branches reach `main`, keep both sets of changes.
- The worktree shares the `feedbin_test` database and the Elasticsearch test indexes with the main checkout. Do not run tests while another session runs tests there.
- Commit messages have no `Co-Authored-By` line and no AI attribution.
- Prefix every shell command with `source ~/.bash_profile &&`.
- Run `bin/rails test` and `bundle exec rake` outside the sandbox. In the sandbox, the test helper fails with `Errno::EPERM` on `bind(2)`.
- Do not pipe test runs through `head` or `tail`. RTK holds the output until the run ends. When a run fails, the full output is in `~/Library/Application Support/rtk/tee/<timestamp>_rake.log`.
- Lint with `bundle exec standardrb --cache false <files>`. Aligned hashes, aligned assignments and aligned tables are house style. Compare offense counts with the `HEAD` versions of the files, and do not "fix" alignment.

## Review Focus

These are the inputs the spec implies that are most likely to cause a problem for a person using this software. Each one has a test in the task named.

1. **Mixed code versions during a rolling deploy.** Deploy A code must read the object rows that the backfill and Deploy B write, and the code before Deploy A must read what Deploy A writes. Expected: no `TypeError`, and the accessors return the stored values. Tests: Task 2.
2. **An app save of an old newsletter row while the backfill runs** (for example `ImageSaver` sets `archived_images`). Expected: the save drops the raw source and `media_image`; it never writes them back. Test: Task 2.
3. **A NUL character in a settings value after Deploy B.** A `jsonb` object cannot hold one, but the old string form could. Expected: the save succeeds and stores the value without the NUL. Test: Task 3.
4. **The backfill runs inside the Rails query cache,** as every Sidekiq job does. Expected: a second run over the same range rewrites nothing. Test: Task 4.
5. **A Mailgun-era row whose payload holds a NUL escape.** SQL cannot parse it. Expected: the Ruby path still copies the sender into `newsletter_from` and removes the payload. Test: Task 4.

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `app/jobs/newsletter_receiver.rb` | 1 | Stop writing the raw source and `newsletter_text` |
| `app/models/email_newsletter.rb` | 1 | Delete the unused `#headers` and `#to_s` |
| `app/jobs/newsletter_updater.rb` | 1 | Delete (dead code, the only reader of the raw source) |
| `test/jobs/newsletter_receiver_test.rb` | 1 | What the receiver stores |
| `app/models/entry_settings_coder.rb` (new) | 2, 3, 5 | Read both forms; write without deleted keys or NUL |
| `test/models/entry_settings_coder_test.rb` (new) | 2, 3, 5 | Unit tests for the coder |
| `app/models/entry.rb` | 2 | The `store :settings` line |
| `test/models/entry_test.rb` | 2, 3, 5 | How `Entry` reads and writes `settings`; two image tests write the old `media_image` straight into the column |
| `app/jobs/backfill_entry_settings.rb` (new, deleted in Task 5) | 4 | The backfill |
| `test/jobs/backfill_entry_settings_test.rb` (new, deleted in Task 5) | 4 | Backfill tests, one for each row shape |
| `app/presenters/entry_presenter.rb` | 5 | Remove the Mailgun fallback in `newsletter_from` |
| `test/presenters/entry_presenter_test.rb` | 5 | `newsletter_from` tests |
| `app/controllers/starred_entries_controller.rb` | 5 | Cache key `v2` to `v3` |
| `app/models/starred_entry.rb` | 5 | `expire_caches` deletes the `v3` key |
| `test/models/starred_entry_test.rb` | 5 | The cache key in the `expire_caches` test |

---

## Deploy A

### Task 1: Stop writing the raw source and `newsletter_text`

**Files:**
- Modify: `app/jobs/newsletter_receiver.rb` (`create_entry`, about line 150)
- Modify: `app/models/email_newsletter.rb` (delete `headers` and `to_s`, about lines 93–101)
- Delete: `app/jobs/newsletter_updater.rb`
- Modify: `test/jobs/newsletter_receiver_test.rb`
- Commit also: `docs/superpowers/specs/2026-10-03-entry-settings-cleanup-design.md`, `docs/superpowers/plans/2026-10-03-entry-settings-cleanup.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a received newsletter entry has `settings` keys `newsletter_from`, `newsletter_to`, `newsletter_token` only, and `data` `{"type" => "newsletter", "format" => "html" | "text", "newsletter_to" => <full token>}`. Nothing in `app/` or `lib/` calls `EmailNewsletter#to_s`, `EmailNewsletter#headers` or `NewsletterUpdater`.

- [ ] **Step 1: Create the worktree and commit the documents**

Use the superpowers:using-git-worktrees skill if it is available. Otherwise run these commands from `~/Sites/feedbin`:

```bash
source ~/.bash_profile && git worktree add -b entry-settings-cleanup .worktrees/entry-settings-cleanup main
```

```bash
source ~/.bash_profile && W=.worktrees/entry-settings-cleanup && mkdir -p $W/.bundle && cp .bundle/config $W/.bundle/ && ln -s ~/Sites/feedbin/.env $W/.env
```

The two documents are untracked files in the main checkout. Copy them into the worktree:

```bash
source ~/.bash_profile && W=.worktrees/entry-settings-cleanup && mkdir -p $W/docs/superpowers/specs $W/docs/superpowers/plans && cp docs/superpowers/specs/2026-10-03-entry-settings-cleanup-design.md $W/docs/superpowers/specs/ && cp docs/superpowers/plans/2026-10-03-entry-settings-cleanup.md $W/docs/superpowers/plans/
```

Run every later command in this plan from inside `~/Sites/feedbin/.worktrees/entry-settings-cleanup`.

A fresh worktree has no built `tailwind.css`, which git ignores. Without it, every controller test that renders a layout errors with `The asset "tailwind.css" is not present in the asset pipeline`. Build it once:

```bash
source ~/.bash_profile && bin/rails tailwindcss:build
```

```bash
source ~/.bash_profile && git add docs/superpowers/specs/2026-10-03-entry-settings-cleanup-design.md docs/superpowers/plans/2026-10-03-entry-settings-cleanup.md && git commit -m "Add the entry settings cleanup spec and plan"
```

- [ ] **Step 2: Write the failing test**

In `test/jobs/newsletter_receiver_test.rb`, add this test directly after the `"Updates Feed"` test:

```ruby
  test "stores the sender and recipient, not the raw source or the text part" do
    NewsletterReceiver.new.perform(@token, @s3_url_html)

    entry = Entry.last
    assert_nil entry.settings["newsletter"]
    assert_equal "Ben Ubois <ben@benubois.com>", entry.newsletter_from
    assert_equal "token@newsletters.feedbin.com", entry.newsletter_to
    assert_equal @token, entry.newsletter_token
    assert_equal({"type" => "newsletter", "format" => "html", "newsletter_to" => @token}, entry.data)
  end
```

In the same file, three `unstorable_attributes` tests build `data` hashes with `newsletter_text`, a key the receiver no longer writes. Change them to `newsletter_to`, which the receiver still writes:

- In `"unstorable_attributes names attributes whose strings are not valid UTF-8"`: change `data: {newsletter_text: invalid_utf8, type: "newsletter"}` to `data: {newsletter_to: invalid_utf8, type: "newsletter"}`, and change the expected value `["content", "data.newsletter_text"]` to `["content", "data.newsletter_to"]`.
- In `"unstorable_attributes is empty when every attribute is storable"`: change `data: {newsletter_text: "fin"}` to `data: {newsletter_to: "fin"}`.
- In `"unstorable_attributes names an attribute carrying a NUL byte"`: change `data: {newsletter_text: "also\0bad"}` to `data: {newsletter_to: "also\0bad"}`, and change the expected value `["title", "data.newsletter_text"]` to `["title", "data.newsletter_to"]`.

- [ ] **Step 3: Run the test to see it fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/newsletter_receiver_test.rb
```

Expected: 20 runs, 1 failure, in `"stores the sender and recipient, not the raw source or the text part"`: `Expected "Date: Tue, 18 May 2021 14:17:41 -0700\r\nFrom: Ben Ubois <ben@benubois.com>..." to be nil`, because `settings["newsletter"]` holds the source. The three changed `unstorable_attributes` tests pass.

- [ ] **Step 4: Change the receiver**

In `app/jobs/newsletter_receiver.rb`, in `create_entry`, delete this line:

```ruby
        newsletter: newsletter.to_s,
```

and replace this line:

```ruby
        data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format, newsletter_to: newsletter.full_token}
```

with:

```ruby
        data: {type: "newsletter", format: newsletter.format, newsletter_to: newsletter.full_token}
```

- [ ] **Step 5: Delete the dead code**

In `app/models/email_newsletter.rb`, delete `headers` and `to_s`. Nothing calls them after Step 4. Replace:

```ruby
  def format
    html ? "html" : "text"
  end

  def headers
    {
      "List-Unsubscribe" => @email["List-Unsubscribe"]&.decoded
    }
  end

  def to_s
    to_utf8(@email.to_s)
  end

  private
```

with:

```ruby
  def format
    html ? "html" : "text"
  end

  private
```

Delete the job that was the only reader of the raw source. Nothing enqueues it, and its write line is commented out:

```bash
source ~/.bash_profile && git rm app/jobs/newsletter_updater.rb
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/newsletter_receiver_test.rb test/models/email_newsletter_test.rb
```

Expected: 28 runs, 0 failures.

- [ ] **Step 7: Check that nothing else uses the deleted code**

```bash
source ~/.bash_profile && git grep -n -P 'NewsletterUpdater|(?<!@)\bnewsletter_text\b' -- app lib test
```

Expected: no output. (`@newsletter_text` in `test/jobs/newsletter_receiver_test.rb` is the text email fixture, so the pattern skips it.)

```bash
source ~/.bash_profile && git grep -n -P '(newsletter|@newsletter)\.(to_s|headers)\b' -- app lib
```

Expected: no output. Do not add `test` here: `test/models/newsletter_test.rb` calls `headers` on the old Mailgun `Newsletter` class, which this plan does not change.

- [ ] **Step 8: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/jobs/newsletter_receiver.rb app/models/email_newsletter.rb test/jobs/newsletter_receiver_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 9: Commit**

```bash
source ~/.bash_profile && git add app/jobs/newsletter_receiver.rb app/models/email_newsletter.rb test/jobs/newsletter_receiver_test.rb && git commit -m "Stop storing the raw newsletter source and newsletter_text"
```

---

### Task 2: `EntrySettingsCoder`, writing the old string form

**Files:**
- Create: `app/models/entry_settings_coder.rb`
- Create: `test/models/entry_settings_coder_test.rb`
- Modify: `app/models/entry.rb:6` (the `store :settings` line)
- Modify: `test/models/entry_test.rb` (new tests, new helpers, and two existing image tests that set `media_image`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `EntrySettingsCoder::DELETED_KEYS` = `%w[newsletter media_image]`.
  - `EntrySettingsCoder.load(value)` → `Hash` for a JSON `String` or a `Hash`, `nil` for `nil` or `""`.
  - `EntrySettingsCoder.dump(hash)` → in this task, a JSON `String` without `DELETED_KEYS` and without NUL characters in string values. Task 3 changes the return value to that `Hash`.
  - `Entry` store accessors: `archived_images`, `newsletter_from`, `embed_duration`, `newsletter_to`, `newsletter_token`. `Entry#newsletter` and `Entry#media_image` no longer exist.
  - Test helpers in `EntryTest`: `write_settings(entry, json)`, `settings_type(entry)`, `read_settings(entry)`.

- [ ] **Step 1: Write the failing coder tests**

Create `test/models/entry_settings_coder_test.rb`:

```ruby
require "test_helper"

class EntrySettingsCoderTest < ActiveSupport::TestCase
  test "load parses the JSON string form that old rows hold" do
    assert_equal({"embed_duration" => 647}, EntrySettingsCoder.load('{"embed_duration":647}'))
  end

  test "load passes the object form through" do
    hash = {"embed_duration" => 647}
    assert_same hash, EntrySettingsCoder.load(hash)
  end

  test "load returns nil for a blank string, which the store passes for a NULL column" do
    assert_nil EntrySettingsCoder.load("")
  end

  test "load returns nil for nil" do
    assert_nil EntrySettingsCoder.load(nil)
  end

  test "dump writes the JSON string form" do
    assert_equal '{"embed_duration":647}', EntrySettingsCoder.dump({"embed_duration" => 647})
  end

  test "dump drops the keys that nothing reads" do
    dumped = EntrySettingsCoder.dump({
      "newsletter" => "From: News <news@example.com>",
      "media_image" => "https://example.com/a.jpg",
      "newsletter_from" => "News <news@example.com>"
    })

    assert_equal({"newsletter_from" => "News <news@example.com>"}, JSON.parse(dumped))
  end

  test "dump removes NUL characters from string values" do
    dumped = EntrySettingsCoder.dump({"newsletter_from" => "Ne\0ws <news@example.com>", "archived_images" => true})

    assert_equal({"newsletter_from" => "News <news@example.com>", "archived_images" => true}, JSON.parse(dumped))
  end
end
```

- [ ] **Step 2: Write the failing `Entry` tests**

In `test/models/entry_test.rb`, add these tests directly before the `private` line:

```ruby
  test "the raw source and media_image are no longer settings accessors" do
    refute_respond_to Entry.new, :newsletter
    refute_respond_to Entry.new, :media_image
  end

  test "settings reads the JSON string form that old rows hold" do
    @entry.save!
    write_settings(@entry, JSON.generate(JSON.generate({"embed_duration" => 647, "newsletter_from" => "News <news@example.com>"})))

    entry = Entry.find(@entry.id)

    assert_equal 647, entry.embed_duration
    assert_equal "News <news@example.com>", entry.newsletter_from
  end

  test "settings reads the object form that the backfill writes" do
    @entry.save!
    write_settings(@entry, JSON.generate({"embed_duration" => 647}))

    assert_equal 647, Entry.find(@entry.id).embed_duration
  end

  test "settings reads a NULL column as empty" do
    @entry.save!
    write_settings(@entry, nil)

    entry = Entry.find(@entry.id)

    assert_equal({}, entry.settings)
    assert_nil entry.embed_duration
  end

  test "a settings write drops the raw source and media_image" do
    @entry.save!
    write_settings(@entry, JSON.generate(JSON.generate({
      "newsletter" => "From: News <news@example.com>",
      "media_image" => "https://example.com/a.jpg",
      "newsletter_from" => "News <news@example.com>"
    })))

    Entry.find(@entry.id).update!(archived_images: true)

    assert_equal({"newsletter_from" => "News <news@example.com>", "archived_images" => true}, read_settings(@entry))
  end

  test "a settings write keeps the JSON string form, which the code before this deploy reads" do
    @entry.save!

    Entry.find(@entry.id).update!(embed_duration: 647)

    assert_equal "string", settings_type(@entry)
    assert_equal({"embed_duration" => 647}, JSON.parse(JSON.parse(raw_settings(@entry))))
  end
```

In the same file, add these helpers directly after the `private` line. `exec_update` does not clear the query cache, which is on in tests, so the reads bypass it:

```ruby
  def write_settings(entry, json)
    Entry.connection.exec_update("UPDATE entries SET settings = $1::jsonb WHERE id = $2", "write_settings", [json, entry.id])
  end

  def raw_settings(entry)
    Entry.uncached { Entry.connection.select_value("SELECT settings::text FROM entries WHERE id = $1", "raw_settings", [entry.id]) }
  end

  def settings_type(entry)
    Entry.uncached { Entry.connection.select_value("SELECT jsonb_typeof(settings) FROM entries WHERE id = $1", "settings_type", [entry.id]) }
  end

  # The stored hash, whichever form the row holds.
  def read_settings(entry)
    value = JSON.parse(raw_settings(entry))
    value.is_a?(String) ? JSON.parse(value) : value
  end
```

Two existing tests in the same file set the old `media_image` value through the accessor that this task removes. They check that no image method reads that value. Keep the check, but write the value straight into the column:

- In `"itunes_image reads the icon row and ignores the legacy url"`, replace:

  ```ruby
      entry.update!(media_image: "https://old.example.com/abc/cover.jpg")
  ```

  with:

  ```ruby
      write_settings(entry, JSON.generate(JSON.generate({"media_image" => "https://old.example.com/abc/cover.jpg"})))
  ```

- In `"legacy JSON alone renders nothing from any image method"`, delete the line `media_image: "https://bucket.s3.amazonaws.com/abc/cover.jpg",` from the `entry.update!(...)` call, and add this line directly after that call:

  ```ruby
    write_settings(entry, JSON.generate(JSON.generate({"media_image" => "https://bucket.s3.amazonaws.com/abc/cover.jpg"})))
  ```

- [ ] **Step 3: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected: 2 failures and 8 errors.
- Every coder test errors with `NameError: uninitialized constant EntrySettingsCoderTest::EntrySettingsCoder`.
- `"the raw source and media_image are no longer settings accessors"` fails: `Entry` still responds to `newsletter`.
- `"settings reads the object form that the backfill writes"` errors with `TypeError: no implicit conversion of Hash into String`. This is the rolling-deploy failure that Task 2 fixes.
- `"a settings write drops the raw source and media_image"` fails: the stored hash still has `newsletter` and `media_image`.
- The other three new `Entry` tests and the two changed image tests pass already.

- [ ] **Step 4: Write the coder**

Create `app/models/entry_settings_coder.rb`:

```ruby
# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows hold the hash as a JSON string inside jsonb. load reads both forms.
# dump drops the keys that nothing reads any more, and the NUL characters
# that a jsonb object cannot hold. Until every process can read objects, dump
# still writes the JSON string form.
class EntrySettingsCoder
  DELETED_KEYS = %w[newsletter media_image].freeze

  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    JSON.generate(value.except(*DELETED_KEYS).transform_values { it.is_a?(String) ? it.delete("\0") : it })
  end
end
```

- [ ] **Step 5: Use it in `Entry`**

In `app/models/entry.rb`, replace line 6:

```ruby
  store :settings, accessors: [:archived_images, :media_image, :newsletter, :newsletter_from, :embed_duration, :newsletter_to, :newsletter_token], coder: JSON
```

with:

```ruby
  store :settings, accessors: [:archived_images, :newsletter_from, :embed_duration, :newsletter_to, :newsletter_token], coder: EntrySettingsCoder
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected: 48 runs, 0 failures.

- [ ] **Step 7: Check that nothing else uses the removed accessors**

```bash
source ~/.bash_profile && git grep -n -P '\.(newsletter|media_image)\b(?!\?|_)' -- app lib ':!*.scss'
```

Expected: exactly four hits, all `entry_presenter.media_image`, in `app/views/entries/_audio_markup.html.erb` (lines 18 and 19) and `app/views/entries/_media.html.erb` (lines 6 and 7). They call `EntryPresenter#media_image`, which reads `itunes_image` and the feed icon, not `settings`. Any other hit must change before you commit.

- [ ] **Step 8: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/entry_settings_coder.rb app/models/entry.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 9: Commit**

```bash
source ~/.bash_profile && git add app/models/entry_settings_coder.rb app/models/entry.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb && git commit -m "Read entry settings in both forms and drop unread keys on write"
```

- [ ] **Step 10: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: 0 failures, 0 errors. If the run fails, read the RTK tee log for the details.

**Deploy A ships Tasks 1 and 2.** Deploy B must wait until Deploy A runs on every web and Sidekiq process.

---

## Deploy B (after Deploy A runs everywhere)

### Task 3: `EntrySettingsCoder` writes objects

**Files:**
- Modify: `app/models/entry_settings_coder.rb`
- Modify: `test/models/entry_settings_coder_test.rb`
- Modify: `test/models/entry_test.rb`

**Interfaces:**
- Consumes: `EntrySettingsCoder` and the `EntryTest` helpers from Task 2.
- Produces: `EntrySettingsCoder.dump(hash)` → `Hash` without `DELETED_KEYS` and without NUL characters in string values. `jsonb` stores it as an object.

- [ ] **Step 1: Change the coder tests to expect a Hash**

In `test/models/entry_settings_coder_test.rb`, replace the three `dump` tests with:

```ruby
  test "dump returns the hash, which jsonb stores as an object" do
    assert_equal({"embed_duration" => 647}, EntrySettingsCoder.dump({"embed_duration" => 647}))
  end

  test "dump drops the keys that nothing reads" do
    dumped = EntrySettingsCoder.dump({
      "newsletter" => "From: News <news@example.com>",
      "media_image" => "https://example.com/a.jpg",
      "newsletter_from" => "News <news@example.com>"
    })

    assert_equal({"newsletter_from" => "News <news@example.com>"}, dumped)
  end

  test "dump removes NUL characters from string values" do
    dumped = EntrySettingsCoder.dump({"newsletter_from" => "Ne\0ws <news@example.com>", "archived_images" => true})

    assert_equal({"newsletter_from" => "News <news@example.com>", "archived_images" => true}, dumped)
  end
```

- [ ] **Step 2: Change the `Entry` tests to expect an object**

In `test/models/entry_test.rb`, replace the test `"a settings write keeps the JSON string form, which the code before this deploy reads"` with these two tests:

```ruby
  test "a settings write stores an object that SQL can read" do
    @entry.save!

    Entry.find(@entry.id).update!(embed_duration: 647)

    assert_equal "object", settings_type(@entry)
    assert_equal "647", Entry.uncached { Entry.connection.select_value("SELECT settings ->> 'embed_duration' FROM entries WHERE id = $1", "embed_duration", [@entry.id]) }
  end

  # A jsonb object cannot hold NUL; the old string form held it as an escape.
  test "a settings value with a NUL character saves without it" do
    @entry.save!

    Entry.find(@entry.id).update!(newsletter_from: "Ne\0ws <news@example.com>")

    assert_equal "News <news@example.com>", Entry.find(@entry.id).newsletter_from
  end
```

- [ ] **Step 3: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected:
- The three coder `dump` tests fail: `dump` returns a `String`, not a `Hash`.
- `"a settings write stores an object that SQL can read"` fails: `Expected: "object"`, `Actual: "string"`.
- `"a settings value with a NUL character saves without it"` passes already, because the Task 2 coder also removes NUL. It guards the object form, where a NUL would make the save raise.

- [ ] **Step 4: Write objects**

In `app/models/entry_settings_coder.rb`, replace the comment and `dump` so the class reads:

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

- [ ] **Step 5: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/entry_settings_coder.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 7: Commit**

```bash
source ~/.bash_profile && git add app/models/entry_settings_coder.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb && git commit -m "Store entry settings as a jsonb object"
```

---

### Task 4: `BackfillEntrySettings`

**Files:**
- Create: `app/jobs/backfill_entry_settings.rb`
- Create: `test/jobs/backfill_entry_settings_test.rb`

**Interfaces:**
- Consumes: `EntrySettingsCoder` (Task 3) only through `Entry`; the job itself writes with SQL.
- Produces:
  - `BackfillEntrySettings::BATCH_SIZE` = `100_000`.
  - `BackfillEntrySettings#perform(batch)`: cleans every row with an ID from `(batch - 1) * BATCH_SIZE + 1` to `batch * BATCH_SIZE`.
  - `BackfillEntrySettings#build`: queues `[1]` up to `[N]`, where `N` is `ceil(Entry.maximum(:id) / BATCH_SIZE)`.

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/backfill_entry_settings_test.rb`:

```ruby
require "test_helper"

class BackfillEntrySettingsTest < ActiveSupport::TestCase
  setup do
    @newsletter_feed = Feed.create!(feed_url: "https://example.com/?#{SecureRandom.hex}", feed_type: :newsletter)
    @other_feed = feeds(:daring_fireball)
  end

  test "a newsletter row keeps the sender, recipient and token, and loses the raw source and text" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "From: News <news@example.com>", "newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "newsletter_token" => "t", "media_image" => "https://example.com/a.jpg"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter", "format" => "html", "newsletter_to" => "t"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "newsletter_token" => "t"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "html", "newsletter_to" => "t"}, row[:data])
  end

  test "a Mailgun-era row gets its sender from the payload, and the payload goes" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("archived_images" => true, "media_image" => "https://example.com/a.jpg"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter", "format" => "html", "newsletter" => {"data" => {"from" => "Old <old@example.com>", "body-html" => "<p>Hello</p>"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"archived_images" => true, "newsletter_from" => "Old <old@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "html"}, row[:data])
  end

  test "a Mailgun-era row with NULL settings gets settings with the sender" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "format" => "text", "newsletter" => {"data" => {"from" => "Old <old@example.com>"}}))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "Old <old@example.com>"}, stored(entry)[:settings])
  end

  test "a sender already in settings is not replaced by the payload's" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter_from" => "Kept <kept@example.com>"),
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"from" => "Other <other@example.com>"}}))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "Kept <kept@example.com>"}, stored(entry)[:settings])
  end

  test "a Mailgun-era row with no sender keeps NULL settings" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"subject" => "Hi"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_nil row[:settings]
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a NUL escape in the raw source goes through the Ruby path" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "a\u0000b", "newsletter_from" => "News <news@example.com>", "newsletter_token" => "t"),
      data: object_form("newsletter_text" => "Hello", "type" => "newsletter"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_token" => "t"}, row[:settings])
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a NUL escape in newsletter_text goes through the Ruby path" do
    entry = entry_with(@newsletter_feed,
      settings: string_form("newsletter" => "From: News <news@example.com>", "newsletter_from" => "News <news@example.com>"),
      data: object_form("newsletter_text" => "a\u0000b", "type" => "newsletter", "format" => "text", "newsletter_to" => "t"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"newsletter_from" => "News <news@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter", "format" => "text", "newsletter_to" => "t"}, row[:data])
  end

  test "a NUL escape in the Mailgun payload still moves the sender into settings" do
    entry = entry_with(@newsletter_feed,
      settings: nil,
      data: object_form("type" => "newsletter", "newsletter" => {"data" => {"from" => "Old <old@example.com>", "body-plain" => "a\u0000b"}}))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"newsletter_from" => "Old <old@example.com>"}, row[:settings])
    assert_equal({"type" => "newsletter"}, row[:data])
  end

  test "a newsletter object row loses media_image and keeps newsletter_to" do
    entry = entry_with(@newsletter_feed,
      settings: object_form("newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com", "media_image" => "https://example.com/a.jpg"),
      data: object_form("type" => "newsletter", "format" => "html"))

    run_backfill(entry)

    assert_equal({"newsletter_from" => "News <news@example.com>", "newsletter_to" => "t@newsletters.feedbin.com"}, stored(entry)[:settings])
  end

  test "another row becomes an object without media_image, and its data does not change" do
    entry = entry_with(@other_feed,
      settings: string_form("embed_duration" => 647, "media_image" => "https://example.com/a.jpg"),
      data: object_form("enclosure_url" => "https://example.com/a.mp3"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal "object", row[:type]
    assert_equal({"embed_duration" => 647}, row[:settings])
    assert_equal({"enclosure_url" => "https://example.com/a.mp3"}, row[:data])
  end

  test "another row with nothing left becomes NULL" do
    media_only = entry_with(@other_feed, settings: string_form("media_image" => "https://example.com/a.jpg"), data: object_form({}))
    empty = entry_with(@other_feed, settings: string_form({}), data: object_form({}))

    run_backfill(media_only, empty)

    assert_nil stored(media_only)[:settings]
    assert_nil stored(empty)[:settings]
  end

  test "a NUL character in another row's settings goes, and its data does not change" do
    entry = entry_with(@other_feed,
      settings: string_form("media_image" => "x\u0000y", "embed_duration" => 5, "archived_images" => true),
      data: object_form("note" => "a\u0000b"))

    run_backfill(entry)

    row = stored(entry)
    assert_equal({"embed_duration" => 5, "archived_images" => true}, row[:settings])
    assert_equal({"note" => "a\u0000b"}, row[:data])
  end

  test "another object row loses media_image" do
    entry = entry_with(@other_feed, settings: object_form("media_image" => "https://example.com/a.jpg", "archived_images" => true), data: object_form({}))

    run_backfill(entry)

    assert_equal({"archived_images" => true}, stored(entry)[:settings])
  end

  test "clean rows and NULL rows are not rewritten" do
    clean_newsletter = entry_with(@newsletter_feed, settings: object_form("newsletter_from" => "News <news@example.com>"), data: object_form("type" => "newsletter", "format" => "html"))
    clean_other = entry_with(@other_feed, settings: object_form("embed_duration" => 3), data: object_form({}))
    null_other = entry_with(@other_feed, settings: nil, data: object_form({}))
    before = [clean_newsletter, clean_other, null_other].map { stored(it)[:ctid] }

    run_backfill(clean_newsletter, clean_other, null_other)

    assert_equal before, [clean_newsletter, clean_other, null_other].map { stored(it)[:ctid] }
  end

  test "the backfill does not change updated_at" do
    entries = [
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "From: a", "newsletter_from" => "A <a@example.com>"), data: object_form("newsletter_text" => "Hello", "type" => "newsletter")),
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "a\u0000b"), data: object_form("type" => "newsletter")),
      entry_with(@other_feed, settings: string_form("embed_duration" => 647), data: object_form({}))
    ]
    before = entries.map { stored(it)[:updated_at] }

    run_backfill(*entries)

    assert_equal before, entries.map { stored(it)[:updated_at] }
  end

  # Sidekiq runs every job inside the Rails executor, where the query cache is
  # on, and exec_update does not clear it.
  test "a second run inside the query cache rewrites nothing" do
    entries = [
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "a\u0000b", "newsletter_from" => "N <n@example.com>"), data: object_form("type" => "newsletter")),
      entry_with(@newsletter_feed, settings: string_form("newsletter" => "From: a", "newsletter_from" => "A <a@example.com>"), data: object_form("newsletter_text" => "Hello", "type" => "newsletter")),
      entry_with(@other_feed, settings: string_form("embed_duration" => 647), data: object_form({}))
    ]

    ActiveRecord::Base.cache do
      run_backfill(*entries)
      after_first = entries.map { stored(it)[:ctid] }

      run_backfill(*entries)

      assert_equal after_first, entries.map { stored(it)[:ctid] }
    end
  end

  test "build queues one job for each range of ids" do
    BackfillEntrySettings.jobs.clear
    entry_with(@other_feed, settings: nil, data: object_form({}))
    batches = (Entry.maximum(:id) / BackfillEntrySettings::BATCH_SIZE.to_f).ceil

    BackfillEntrySettings.new.build

    assert_equal batches, BackfillEntrySettings.jobs.size
    assert_equal [1], BackfillEntrySettings.jobs.first["args"]
    assert_equal [batches], BackfillEntrySettings.jobs.last["args"]
  end

  private

  # Writes settings and data exactly as a production row holds them.
  def entry_with(feed, settings:, data:)
    entry = feed.entries.create!(public_id: SecureRandom.hex, content: "<p>Body.</p>")
    Entry.connection.exec_update("UPDATE entries SET settings = $1::jsonb, data = $2::json WHERE id = $3", "entry_with", [settings, data, entry.id])
    entry
  end

  # Today's form: the hash as a JSON string inside jsonb.
  def string_form(hash)
    JSON.generate(JSON.generate(hash))
  end

  def object_form(hash)
    JSON.generate(hash)
  end

  def stored(entry)
    row = Entry.uncached do
      Entry.connection.select_one(
        "SELECT jsonb_typeof(settings) AS type, settings::text AS settings, data::text AS data, ctid::text AS ctid, updated_at::text AS updated_at FROM entries WHERE id = $1",
        "stored", [entry.id]
      )
    end
    settings = row["settings"] && JSON.parse(row["settings"])
    settings = JSON.parse(settings) if settings.is_a?(String)
    {type: row["type"], settings: settings, data: row["data"] && JSON.parse(row["data"]), ctid: row["ctid"], updated_at: row["updated_at"]}
  end

  # The entries of one test can straddle a range boundary, so run every range
  # they touch.
  def run_backfill(*entries)
    entries.map { (it.id - 1) / BackfillEntrySettings::BATCH_SIZE + 1 }.uniq.each { BackfillEntrySettings.new.perform(it) }
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/backfill_entry_settings_test.rb
```

Expected: every test errors with `NameError: uninitialized constant BackfillEntrySettingsTest::BackfillEntrySettings`.

- [ ] **Step 3: Write the job**

Create `app/jobs/backfill_entry_settings.rb`:

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

Notes for the implementer:
- Every `CASE` that checks for `\u0000` must come before the first cast or `->`. Postgres does not promise any order for `AND`, and one row with the escape would abort the whole statement.
- The unwrap expression appears twice in `NEWSLETTER_SQL` on purpose. The project forbids building SQL by interpolation, even from constants.

- [ ] **Step 4: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/backfill_entry_settings_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 5: Check the query-cache guard**

Temporarily remove the `Entry.uncached do` line and its matching `end` from `perform`, and run:

```bash
source ~/.bash_profile && bin/rails test test/jobs/backfill_entry_settings_test.rb
```

Expected: `"a second run inside the query cache rewrites nothing"` fails, because the second run repairs the NUL row again. Restore the two lines and run the file again. Expected: PASS.

- [ ] **Step 6: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/jobs/backfill_entry_settings.rb test/jobs/backfill_entry_settings_test.rb
```

Expected: no offenses.

- [ ] **Step 7: Commit**

```bash
source ~/.bash_profile && git add app/jobs/backfill_entry_settings.rb test/jobs/backfill_entry_settings_test.rb && git commit -m "Add BackfillEntrySettings to clean entry settings and newsletter data"
```

- [ ] **Step 8: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: 0 failures, 0 errors. If the run fails, read the RTK tee log for the details.

**Deploy B ships Tasks 3 and 4.**

---

## Backfill (after Deploy B)

Ben runs these steps. They are not code changes.

1. Limit the concurrency of the `utility` queue.
2. In a production console, run `BackfillEntrySettings.new.build`. It queues 53,921 jobs.
3. While it runs, watch replication lag, WAL volume, and autovacuum on `entries` and its TOAST table. The spec estimates about 29 million row versions and at least 60 GiB of WAL.
4. When `BackfillEntrySettings.progress[:pending]` is `0`, the pass is done. Run `BackfillEntrySettings.new.build` again. The second pass catches rows that changed during the first one.
5. Repeat until a pass ends with `pending: 0, changed: 0, repaired: 0` in `BackfillEntrySettings.progress`. That is the completion gate.
6. Optional spot check: run Block 4 from the spec's appendix on the production console. It reads the 0.1% sample, and all three counts must be `0`.

The final review added two things to the job after Task 4 (commits `80ebdb62` and `353ef36b`): each statement covers at most 5,000 IDs (`SUB_RANGE`), because production cancels a statement after 15 s and an app lock wait after 10 s; and the Redis pass counters behind `BackfillEntrySettings.progress`, because a full-table check cannot finish under that timeout.

---

## Deploy C (after a backfill pass that changed and repaired nothing)

### Task 5: Remove the fallbacks and the backfill

**Files:**
- Modify: `app/models/entry_settings_coder.rb`
- Modify: `test/models/entry_settings_coder_test.rb`
- Modify: `app/presenters/entry_presenter.rb` (`newsletter_from`, about line 145)
- Modify: `test/presenters/entry_presenter_test.rb`
- Modify: `app/controllers/starred_entries_controller.rb:9`
- Modify: `app/models/starred_entry.rb:27` (`expire_caches`)
- Modify: `test/models/starred_entry_test.rb:51`
- Delete: `app/jobs/backfill_entry_settings.rb`
- Delete: `test/jobs/backfill_entry_settings_test.rb`

**Interfaces:**
- Consumes: the coder from Task 3. The backfill from Task 4 has run, and a pass ends with `pending: 0, changed: 0, repaired: 0` in `BackfillEntrySettings.progress`.
- Produces:
  - `EntrySettingsCoder.dump(hash)` → the `Hash` without NUL characters in string values. `DELETED_KEYS` no longer exists.
  - `EntryPresenter#newsletter_from` reads `entry.newsletter_from` only.
  - The starred feed cache key is `"#{user_id}:starred_feed:v3"`, in both `StarredEntriesController#index` and `StarredEntry#expire_caches`.

- [ ] **Step 1: Write the failing presenter tests**

In `test/presenters/entry_presenter_test.rb`, add these tests directly after the `entry_with` helper method:

```ruby
  test "newsletter_from reads the sender from settings" do
    entry = entry_with(newsletter_from: "\"Example News\" <news@example.com>")

    from = presenter_for(entry).newsletter_from

    assert_equal "Example News", from.name
    assert_equal "news@example.com", from.address
  end

  test "newsletter_from ignores the old Mailgun payload in data" do
    entry = entry_with(data: {"newsletter" => {"data" => {"from" => "Old <old@example.com>"}}})

    assert_nil presenter_for(entry).newsletter_from
  end
```

- [ ] **Step 2: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/presenters/entry_presenter_test.rb
```

Expected: `"newsletter_from ignores the old Mailgun payload in data"` fails with `Expected #<OpenStruct name="Old", address="old@example.com"> to be nil.`, because the fallback returns the old sender. `"newsletter_from reads the sender from settings"` passes already.

- [ ] **Step 3: Remove the fallback**

In `app/presenters/entry_presenter.rb`, in `newsletter_from`, replace:

```ruby
    from = entry.newsletter_from || entry.data && entry.data.safe_dig("newsletter", "data", "from")
```

with:

```ruby
    from = entry.newsletter_from
```

- [ ] **Step 4: Remove the deleted keys from the coder**

In `test/models/entry_settings_coder_test.rb`, delete the test `"dump drops the keys that nothing reads"`.

Replace `app/models/entry_settings_coder.rb` with:

```ruby
# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows held the hash as a JSON string inside jsonb. load reads both forms.
# dump writes a real object. A jsonb object cannot hold NUL, so dump removes
# it from string values.
class EntrySettingsCoder
  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    value.transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end
end
```

In `test/models/entry_test.rb`, delete the test `"a settings write drops the raw source and media_image"`. With this coder it fails, because the coder keeps every key. After the backfill, no row holds those keys, and no accessor writes them.

- [ ] **Step 5: Change the starred feed cache key**

The `v2` values hold full `Entry` objects with the old `settings` and `data`. They have no expiry, so Redis keeps them until it evicts them. Two places use the key: the controller reads it, and `StarredEntry#expire_caches` deletes it when a star changes. Both must change together, or a star change no longer clears the cached feed.

In `test/models/starred_entry_test.rb`, in `"expire_caches deletes the user's starred feed cache"`, replace:

```ruby
    cache_key = "#{@user.id}:starred_feed:v2"
```

with:

```ruby
    cache_key = "#{@user.id}:starred_feed:v3"
```

Run it:

```bash
source ~/.bash_profile && bin/rails test test/models/starred_entry_test.rb
```

Expected: 1 failure: `Expected "cached value" to be nil.`

In `app/models/starred_entry.rb`, replace:

```ruby
    Rails.cache.delete("#{user_id}:starred_feed:v2")
```

with:

```ruby
    Rails.cache.delete("#{user_id}:starred_feed:v3")
```

In `app/controllers/starred_entries_controller.rb`, replace:

```ruby
      @entries = Rails.cache.fetch("#{@user.id}:starred_feed:v2") {
```

with:

```ruby
      @entries = Rails.cache.fetch("#{@user.id}:starred_feed:v3") {
```

- [ ] **Step 6: Delete the backfill**

```bash
source ~/.bash_profile && git rm app/jobs/backfill_entry_settings.rb test/jobs/backfill_entry_settings_test.rb
```

- [ ] **Step 7: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/presenters/entry_presenter_test.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb test/models/starred_entry_test.rb test/controllers/starred_entries_controller_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 8: Check that nothing reads the deleted values**

```bash
source ~/.bash_profile && git grep -n -P 'safe_dig\("newsletter"|DELETED_KEYS|BackfillEntrySettings|starred_feed:v2' -- app lib test
```

Expected: no output.

- [ ] **Step 9: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/entry_settings_coder.rb app/presenters/entry_presenter.rb app/controllers/starred_entries_controller.rb app/models/starred_entry.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb test/models/starred_entry_test.rb test/presenters/entry_presenter_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 10: Commit**

```bash
source ~/.bash_profile && git add -A app/models/entry_settings_coder.rb app/presenters/entry_presenter.rb app/controllers/starred_entries_controller.rb app/models/starred_entry.rb test/models/entry_settings_coder_test.rb test/models/entry_test.rb test/models/starred_entry_test.rb test/presenters/entry_presenter_test.rb && git commit -m "Remove the settings cleanup fallbacks and the backfill"
```

- [ ] **Step 11: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: 0 failures, 0 errors.

**Deploy C ships Task 5.**
