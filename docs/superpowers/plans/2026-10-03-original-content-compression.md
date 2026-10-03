# Compressed Original Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `entries.original` JSON column with a small `bytea` column that holds only the first version of the content, compressed with zstd against the current content.

**Architecture:** A stateless `OriginalContent` module compresses and decompresses the value. `Entry` reads it through `original_content` and keeps it valid with a `before_save` callback. `FeedCrawler::EntryUpdate` writes it, and API v2 rebuilds the old `original` hash from the current columns. Deploy 1 ships all of this plus a Sidekiq backfill and stops loading `original`. Deploy 2 drops `original`.

**Tech Stack:** Ruby 4.0.7, Rails 8.1.4, Postgres 11 (production), Minitest 6, Sidekiq, the `zstd-ruby` gem, strong_migrations.

**Spec:** `docs/superpowers/specs/2026-10-03-original-content-compression-design.md`

**Runbook:** `docs/ops/original-content-compression-runbook.html` (the deploy and backfill steps, with checkboxes)

## Global Constraints

- New column: `entries.compressed_original_content`, type `bytea` (Rails `:binary`), nullable, no default.
- Value layout: bytes 0–3 are the CRC32 of the current `content`, big-endian (`pack("N")`). Bytes 4 and after are one zstd frame of the original content at level 3, with the current `content` as the dictionary.
- Gem: `zstd-ruby`. Require name: `zstd-ruby`. Constant: `Zstd`.
- API v2 `original` keeps 8 keys in this order: `author`, `content`, `title`, `url`, `entry_id`, `published`, `data`, `fingerprint`. `published` keeps the format `YYYY-MM-DDTHH:MM:SS.sssZ`. The value is `null` when the entry has no original.
- `Entry#original_content` has no legacy fallback. It reads only `compressed_original_content`.
- Deploy 1 adds `original` to `Entry.ignored_columns`. Deploy 2 drops the column and removes that line.
- Backfill: queue `utility`, 100,000-ID ranges (`BATCH_SIZE = 100_000`), newest range first, one `update_all` for each row, with `updated_at` in the `WHERE` condition.
- With `original` ignored, write it in tests with `Entry.where(id: ...).update_all(original: hash.to_json)` and read it with `Entry.where(id: ...).pick(:original)`. `update_columns(original: ...)` raises `ActiveModel::MissingAttributeError`, and `update_all` with a Hash raises `TypeError: can't cast Hash`.
- Never interpolate values or identifiers into SQL. Use Active Record, Arel, or bind parameters.
- Every migration must pass strong_migrations (`StrongMigrations.target_version = 11`).
- Work on the branch `original-content-compression`, not on `main`.
- Commit messages have no `Co-Authored-By` line and no AI attribution.
- Prefix every shell command with `source ~/.bash_profile &&`.
- Run `bin/rails test` and `bundle exec rake` outside the sandbox. In the sandbox, the test helper fails with `Errno::EPERM` on `bind(2)`.
- Do not pipe test runs through `head` or `tail`. RTK holds the output until the run ends. When a run fails, the full output is in `~/Library/Application Support/rtk/tee/<timestamp>_rake.log`.
- Lint with `bundle exec standardrb --cache false <files>`. Aligned hashes, aligned assignments, and aligned tables are house style. Compare offense counts with the `HEAD` versions of the files, and do not "fix" alignment.
- Deploy order: Deploy 1 (Tasks 1–5), then the backfill, then Deploy 2 (Task 6).

## Review Focus

These are the inputs the spec implies that are most likely to cause a problem for a person using this software. Each one has a test in the task named.

1. **Content changed by code that skips callbacks after an original exists.** Expected: `original_content` and `content_diff` return `nil`, and API v2 `original` is `null`. Never wrong text, never an exception. Test: Task 2.
2. **Content changed to an empty string after an original exists.** Expected: the save succeeds, and the stored value is cleared. Test: Task 2.
3. **A significant update to an entry the backfill has not converted yet.** Expected: `EntryUpdate` writes a temporary original and leaves the legacy column alone. Later, the backfill replaces the temporary value with the legacy one. Tests: Task 5.
4. **An original much larger than a tiny current content** (production has a 28.5 KB original with 112 bytes of current content). Expected: an exact round trip. Test: Task 1.
5. **The backfill runs a second time over the same range.** Expected: the second run changes nothing, and converted values stay. Test: Task 5.

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `Gemfile`, `Gemfile.lock` | 1 | Add `zstd-ruby` |
| `app/models/original_content.rb` (new) | 1 | Compress and decompress the value. No state, no Active Record. |
| `test/models/original_content_test.rb` (new) | 1 | Unit tests for the module |
| `db/migrate/20261003120000_add_compressed_original_content_to_entries.rb` (new) | 2 | Add the column |
| `db/structure.sql` | 2, 6 | Generated schema |
| `app/models/entry.rb` | 2, 5, 6 | `original_content`, the recompress callback, `content_diff`, `ignored_columns` |
| `test/models/entry_test.rb` | 2, 5, 6 | Model tests |
| `test/system/article_test.rb` | 2 | The "diff" system test |
| `app/jobs/feed_crawler/lib/entry_update.rb` | 3 | Write the compressed original at the first significant change |
| `test/jobs/feed_crawler/entry_update_test.rb` (new) | 3, 5, 6 | EntryUpdate tests |
| `test/jobs/feed_crawler/receiver_test.rb` | 3 | One assertion changes |
| `app/presenters/entry_presenter.rb` | 4 | `api_original` |
| `app/views/api/v2/entries/_entry_default.json.jbuilder` | 4 | Use `api_original` |
| `app/views/api/v2/entries/_entry_extended.json.jbuilder` | 4 | Use `api_original` |
| `test/presenters/entry_presenter_test.rb` | 4 | Presenter tests |
| `test/controllers/api/v2/entries_controller_test.rb` | 4 | API tests |
| `app/jobs/backfill_original_content.rb` (new, deleted in Task 6) | 5 | Backfill job |
| `test/jobs/backfill_original_content_test.rb` (new, deleted in Task 6) | 5 | Backfill tests |
| `db/migrate/20261003130000_remove_original_from_entries.rb` (new) | 6 | Drop `original` |

---

## Deploy 1

### Task 1: zstd gem and the `OriginalContent` module

**Files:**
- Modify: `Gemfile` (after `gem "web-push"`)
- Modify: `Gemfile.lock`
- Create: `app/models/original_content.rb`
- Create: `test/models/original_content_test.rb`
- Commit also: `docs/superpowers/specs/2026-10-03-original-content-compression-design.md`, `docs/superpowers/plans/2026-10-03-original-content-compression.md`, `docs/ops/original-content-compression-runbook.html`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `OriginalContent.compress(original, base:)` → binary `String`, or `nil` when `original` or `base` is blank.
  - `OriginalContent.decompress(blob, base:)` → UTF-8 `String`, or `nil` when `blob` is `nil`, `base` is blank, the CRC does not match, or zstd raises. On a zstd error, it calls `ErrorService.notify(error_class: "OriginalContent#decompress", error_message: "zstd decompress failed", parameters: {exception: exception})`.

- [ ] **Step 1: Create the branch and commit the documents**

If you are not already in a worktree on this branch:

```bash
source ~/.bash_profile && git checkout -b original-content-compression
```

```bash
source ~/.bash_profile && git add docs/superpowers/specs/2026-10-03-original-content-compression-design.md docs/superpowers/plans/2026-10-03-original-content-compression.md docs/ops/original-content-compression-runbook.html && git commit -m "Add the original content compression spec, plan, and runbook"
```

- [ ] **Step 2: Add the gem**

In `Gemfile`, add this line directly after `gem "web-push"`:

```ruby
gem "zstd-ruby"
```

Run `bundle install`. Do not use `bundle lock --local`, because it removes the generic `ruby` platform entries from the lock file.

```bash
source ~/.bash_profile && bundle install
```

Check the lock file change:

```bash
source ~/.bash_profile && git diff Gemfile.lock
```

Expected: only two added lines, `zstd-ruby (<version>)` under `specs:` and `zstd-ruby` under `DEPENDENCIES`. If other lines change, restore the lock file with `git checkout Gemfile.lock` and edit it by hand.

- [ ] **Step 3: Write the failing tests**

Create `test/models/original_content_test.rb`:

```ruby
require "test_helper"

class OriginalContentTest < ActiveSupport::TestCase
  test "round trip returns the original as UTF-8" do
    base = "<p>Café ★ 日本語 with an added sentence.</p>"
    original = "<p>Café ★ 日本語.</p>"

    blob = OriginalContent.compress(original, base: base)
    result = OriginalContent.decompress(blob, base: base)

    assert_equal original, result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test "round trip uses the dictionary past 32 KB" do
    base = SecureRandom.alphanumeric(40_000)
    original = base[0, 20_000] + base[20_100..]

    blob = OriginalContent.compress(original, base: base)

    assert_operator blob.bytesize, :<, 200
    assert_equal original, OriginalContent.decompress(blob, base: base)
  end

  test "round trip works when the current content is much shorter than the original" do
    original = SecureRandom.alphanumeric(28_000)
    base = "<p>Removed</p>"

    blob = OriginalContent.compress(original, base: base)

    assert_equal original, OriginalContent.decompress(blob, base: base)
  end

  test "decompress returns nil when the base changed" do
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>Old text and new text.</p>")

    assert_nil OriginalContent.decompress(blob, base: "<p>Old text and newer text.</p>")
  end

  test "decompress returns nil without a value or a base" do
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>New text.</p>")

    assert_nil OriginalContent.decompress(nil, base: "<p>New text.</p>")
    assert_nil OriginalContent.decompress(blob, base: "")
    assert_nil OriginalContent.decompress(blob, base: nil)
  end

  test "compress returns nil without an original or a base" do
    assert_nil OriginalContent.compress("", base: "<p>New text.</p>")
    assert_nil OriginalContent.compress(nil, base: "<p>New text.</p>")
    assert_nil OriginalContent.compress("<p>Old text.</p>", base: "")
    assert_nil OriginalContent.compress("<p>Old text.</p>", base: nil)
  end

  test "decompress reports a damaged value and returns nil" do
    base = "<p>New text.</p>"
    blob = OriginalContent.compress("<p>Old text.</p>", base: base)
    damaged = blob.byteslice(0, 4) + "not a zstd frame".b
    notified = []

    ErrorService.stub(:notify, ->(options) { notified << options }) do
      assert_nil OriginalContent.decompress(damaged, base: base)
    end

    assert_equal ["OriginalContent#decompress"], notified.map { _1[:error_class] }
  end
end
```

The damaged value keeps the correct CRC but replaces the zstd frame. zstd-ruby raises `RuntimeError: not a zstd frame (magic not found)` for it.

- [ ] **Step 4: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/models/original_content_test.rb
```

Expected: FAIL. Each test errors with `NameError: uninitialized constant OriginalContentTest::OriginalContent`.

- [ ] **Step 5: Write the module**

Create `app/models/original_content.rb`:

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

- [ ] **Step 6: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/models/original_content_test.rb
```

Expected: PASS, 7 runs, 0 failures.

- [ ] **Step 7: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/original_content.rb test/models/original_content_test.rb
```

Expected: no offenses.

- [ ] **Step 8: Commit**

```bash
source ~/.bash_profile && git add Gemfile Gemfile.lock app/models/original_content.rb test/models/original_content_test.rb && git commit -m "Add OriginalContent: zstd compression of the first content version against the current content"
```

---

### Task 2: The column and the `Entry` changes

**Files:**
- Create: `db/migrate/20261003120000_add_compressed_original_content_to_entries.rb`
- Modify: `db/structure.sql` (generated by the migration)
- Modify: `app/models/entry.rb` (callbacks near line 29, `content_diff` near line 202, the `private` section near line 366)
- Modify: `test/models/entry_test.rb` (new tests before `private` near line 391, a helper after it)
- Modify: `test/system/article_test.rb` (the "diff" test near line 83)

This task does not ignore `original` yet. `EntryUpdate` and the API templates still read it until Tasks 3 and 4 change them. Task 5 adds the ignore.

**Interfaces:**
- Consumes: `OriginalContent.compress(original, base:)` and `OriginalContent.decompress(blob, base:)` from Task 1.
- Produces:
  - Column `entries.compressed_original_content` (`bytea`).
  - `Entry#original_content` → `String` or `nil`. It reads only `compressed_original_content`.
  - `Entry#content_diff` reads `original_content`.
  - Private callback `Entry#recompress_original_content` (`before_save`).

- [ ] **Step 1: Write the migration**

Create `db/migrate/20261003120000_add_compressed_original_content_to_entries.rb`:

```ruby
class AddCompressedOriginalContentToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :compressed_original_content, :binary
  end
end
```

On Postgres 11, adding a nullable column with no default changes only the catalog, so strong_migrations accepts it.

- [ ] **Step 2: Run the migration on the dev database**

```bash
source ~/.bash_profile && bin/rails db:migrate
```

Check the schema change:

```bash
source ~/.bash_profile && git diff db/structure.sql
```

Expected: one added line `compressed_original_content bytea` in `CREATE TABLE public.entries`, and `('20261003120000')` added to the `schema_migrations` insert. If the local `pg_dump` adds unrelated changes, keep only these two hunks.

- [ ] **Step 3: Write the failing model tests**

In `test/models/entry_test.rb`, add these tests directly before the `private` line (near line 391):

```ruby
  test "original_content reads the compressed column" do
    entry = saved_entry("<p>Old text.</p><p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "original_content survives later content changes" do
    entry = saved_entry("<p>First.</p>")
    second = "<p>First.</p><p>Second.</p>"
    entry.update!(content: second, compressed_original_content: OriginalContent.compress("<p>First.</p>", base: second))
    entry.update!(content: "<p>First.</p><p>Second.</p><p>Third.</p>")
    entry.update!(content: "<p>Only the fourth version.</p>")

    assert_equal "<p>First.</p>", entry.reload.original_content
  end

  test "a save that sets the compressed column with new content keeps the new value" do
    entry = saved_entry("<p>Old text.</p>")
    blob = OriginalContent.compress("<p>Old text.</p>", base: "<p>New text.</p>")
    entry.update!(content: "<p>New text.</p>", compressed_original_content: blob)

    assert_equal blob, entry.reload.compressed_original_content
  end

  test "a save without a content change keeps the stored value" do
    entry = saved_entry("<p>New text.</p>")
    blob = OriginalContent.compress("<p>Old text.</p>", base: entry.content)
    entry.update!(compressed_original_content: blob)
    entry.update!(title: "A new title")

    assert_equal blob, entry.reload.compressed_original_content
  end

  test "content changed outside callbacks makes original_content nil" do
    entry = saved_entry("<p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))
    entry.update_columns(content: "<p>Rewritten without callbacks.</p>")

    entry.reload
    assert_nil entry.original_content
    assert_nil entry.content_diff
  end

  test "content changed to blank clears the stored value" do
    entry = saved_entry("<p>New text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))
    entry.update!(content: "")

    assert_nil entry.reload.compressed_original_content
  end

  test "content_diff marks the added text" do
    entry = saved_entry("<p>This is the text.</p>")
    entry.update!(
      content: "<p>This is the new text.</p>",
      compressed_original_content: OriginalContent.compress("<p>This is the text.</p>", base: "<p>This is the new text.</p>")
    )

    assert_match %r{<ins>new\s*</ins>}, entry.reload.content_diff
  end

  test "content_diff is nil without an original" do
    assert_nil saved_entry("<p>Text.</p>").content_diff
  end
```

In the same file, add this helper directly after the `private` line:

```ruby
  def saved_entry(content)
    @user.feeds.first.entries.create!(public_id: SecureRandom.hex, content: content)
  end
```

- [ ] **Step 4: Run the model tests to see them fail**

Minitest turns the spaces in a test name into underscores, so the pattern uses underscores.

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb -n "/original_content|compressed_column|stored_value|content_changed|content_diff/"
```

Expected: FAIL. The tests error with `NoMethodError: undefined method 'original_content'`, and the content-change tests fail because nothing re-encodes the value.

- [ ] **Step 5: Add the callback, the reader, and the new `content_diff`**

In `app/models/entry.rb`, add the callback directly after `before_update :create_summary`:

```ruby
  before_save :recompress_original_content
```

Replace the whole `content_diff` method (near line 202) with these two methods:

```ruby
  def original_content
    OriginalContent.decompress(compressed_original_content, base: content)
  end

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

Add this method directly after the `private` line of `Entry` (near line 366):

```ruby
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

- [ ] **Step 6: Run the model tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb
```

Expected: PASS, with 0 failures for the whole file.

- [ ] **Step 7: Move the system test to the new column**

In `test/system/article_test.rb`, in the `test "diff"` block, replace this line:

```ruby
    entry.update(content: "<p>This is the new text.</p>", original: {content: entry.content})
```

with:

```ruby
    new_content = "<p>This is the new text.</p>"
    entry.update(content: new_content, compressed_original_content: OriginalContent.compress(entry.content, base: new_content))
```

Ruby evaluates `entry.content` before the update, so the original is `"<p>This is the text.</p>"`.

- [ ] **Step 8: Run the system test**

Pass the file path. `bin/rails test:system` ignores `TEST=` and runs every system test.

```bash
source ~/.bash_profile && bin/rails test test/system/article_test.rb -n test_diff
```

Expected: PASS, 1 run, 0 failures.

- [ ] **Step 9: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/entry.rb test/models/entry_test.rb test/system/article_test.rb db/migrate/20261003120000_add_compressed_original_content_to_entries.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 10: Commit**

```bash
source ~/.bash_profile && git add db/migrate/20261003120000_add_compressed_original_content_to_entries.rb db/structure.sql app/models/entry.rb test/models/entry_test.rb test/system/article_test.rb && git commit -m "Store the original content compressed in compressed_original_content and diff against it"
```

---

### Task 3: `EntryUpdate` writes the compressed original

**Files:**
- Modify: `app/jobs/feed_crawler/lib/entry_update.rb:18-31`
- Create: `test/jobs/feed_crawler/entry_update_test.rb`
- Modify: `test/jobs/feed_crawler/receiver_test.rb` (the "should not create original nil content" test near line 91)

**Interfaces:**
- Consumes: `OriginalContent.compress(original, base:)` (Task 1). `Entry#original_content` and the `compressed_original_content` column (Task 2).
- Produces: at the first significant change of an entry with `published_recently?`, `EntryUpdate` sets `compressed_original_content` to `OriginalContent.compress(old_content, base: new_content)`. It never writes `original`.

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/feed_crawler/entry_update_test.rb`:

```ruby
require "test_helper"

module FeedCrawler
  class EntryUpdateTest < ActiveSupport::TestCase
    setup do
      @feed = users(:ben).subscriptions.first.feed
      @old_content = "<p>#{"Original sentence. " * 5}</p>"
      @entry = @feed.entries.create!(url: "url", public_id: SecureRandom.hex, content: @old_content, published: Time.now)
    end

    test "first significant change stores the old content as the original" do
      new_content = significant(@old_content)

      EntryUpdate.create!(update_data(new_content), @entry)

      entry = @entry.reload
      assert_equal new_content, entry.content
      assert_equal @old_content, entry.original_content
    end

    test "second significant change keeps the first original" do
      second = significant(@old_content)
      EntryUpdate.create!(update_data(second), @entry)

      EntryUpdate.create!(update_data(significant(second)), @entry.reload)

      assert_equal @old_content, @entry.reload.original_content
    end

    test "small change keeps the original" do
      second = significant(@old_content)
      EntryUpdate.create!(update_data(second), @entry)
      third = second.sub("Original", "Changed")

      EntryUpdate.create!(update_data(third), @entry.reload)

      entry = @entry.reload
      assert_equal third, entry.content
      assert_equal @old_content, entry.original_content
    end

    test "small change on an entry without an original stores nothing" do
      EntryUpdate.create!(update_data(@old_content.sub("Original", "Changed")), @entry)

      assert_nil @entry.reload.compressed_original_content
    end

    test "significant change on an old entry stores nothing" do
      @entry.update_columns(published: 8.days.ago)

      EntryUpdate.create!(update_data(significant(@old_content)), @entry.reload)

      assert_nil @entry.reload.compressed_original_content
    end

    private

    def update_data(content)
      {
        "author" => @entry.author,
        "content" => content,
        "title" => @entry.title,
        "url" => @entry.url,
        "entry_id" => @entry.entry_id,
        "data" => @entry.data
      }
    end

    # significant_change? needs more than 50 more characters of text.
    def significant(content)
      content + "<p>#{"An added paragraph with many more words. " * 3}</p>"
    end
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/feed_crawler/entry_update_test.rb
```

Expected: FAIL. "first significant change stores the old content as the original", "second significant change keeps the first original", and "small change keeps the original" fail because `original_content` is `nil`. `EntryUpdate` still writes the 8-field `original` hash, and `original_content` does not read that column.

- [ ] **Step 3: Change `EntryUpdate`**

In `app/jobs/feed_crawler/lib/entry_update.rb`, replace this block:

```ruby
        if @original_entry.original.nil?
          update["original"] = {
            "author"      => @original_entry.author,
            "content"     => @original_entry.content,
            "title"       => @original_entry.title,
            "url"         => @original_entry.url,
            "entry_id"    => @original_entry.entry_id,
            "published"   => @original_entry.published,
            "data"        => @original_entry.data,
            "fingerprint" => @original_entry.fingerprint,
          }
        end
```

with:

```ruby
        if @original_entry.original_content.nil?
          update["compressed_original_content"] = OriginalContent.compress(current_content, base: new_content)
        end
```

`current_content` is the content before this update, so it becomes the original. `new_content` is the content after this update, so it is the dictionary. The `Entry` callback skips this save, because the save also sets the column.

- [ ] **Step 4: Change the receiver test**

In `test/jobs/feed_crawler/receiver_test.rb`, in `test "should not create original nil content"`, replace:

```ruby
      assert_nil entry.reload.original
```

with:

```ruby
      assert_nil entry.reload.compressed_original_content
```

- [ ] **Step 5: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/feed_crawler/entry_update_test.rb test/jobs/feed_crawler/receiver_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/jobs/feed_crawler/lib/entry_update.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/feed_crawler/receiver_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 7: Commit**

```bash
source ~/.bash_profile && git add app/jobs/feed_crawler/lib/entry_update.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/feed_crawler/receiver_test.rb && git commit -m "EntryUpdate stores the first version as compressed_original_content"
```

---

### Task 4: API v2 `original` from the current columns

**Files:**
- Modify: `app/presenters/entry_presenter.rb` (add `api_original` after `api_content`, near line 161)
- Modify: `app/views/api/v2/entries/_entry_default.json.jbuilder:8`
- Modify: `app/views/api/v2/entries/_entry_extended.json.jbuilder:7`
- Modify: `test/presenters/entry_presenter_test.rb`
- Modify: `test/controllers/api/v2/entries_controller_test.rb`

**Interfaces:**
- Consumes: `Entry#original_content` (Task 2).
- Produces: `EntryPresenter#api_original` → `nil`, or a `Hash` with the symbol keys `:author, :content, :title, :url, :entry_id, :published, :data, :fingerprint`, in that order. `:content` is `original_content`. The other values are the entry's current columns.

- [ ] **Step 1: Write the failing presenter tests**

In `test/presenters/entry_presenter_test.rb`, add these tests before the final `end` of the class:

```ruby
  test "api_original keeps the old shape with the original content and current values" do
    content = "<p>Old text.</p><p>New text.</p>"
    fingerprint = SecureRandom.uuid
    entry = @feed.entries.create!(
      public_id: SecureRandom.hex,
      title: "Current title",
      author: "Current author",
      url: "https://example.com/post",
      entry_id: "entry-1",
      fingerprint: fingerprint,
      content: content,
      data: {"media" => []}
    )
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: content))
    entry.reload

    result = presenter_for(entry).api_original

    assert_equal %i[author content title url entry_id published data fingerprint], result.keys
    assert_equal "<p>Old text.</p>", result[:content]
    assert_equal ["Current author", "Current title", "https://example.com/post", "entry-1"], result.values_at(:author, :title, :url, :entry_id)
    assert_equal entry.published, result[:published]
    assert_equal({"media" => []}, result[:data])
    assert_equal fingerprint, result[:fingerprint]
  end

  test "api_original is nil without an original" do
    entry = @feed.entries.create!(public_id: SecureRandom.hex, content: "<p>Text.</p>")

    assert_nil presenter_for(entry).api_original
  end
```

- [ ] **Step 2: Write the failing API tests**

In `test/controllers/api/v2/entries_controller_test.rb`, add these tests directly before the `private` line:

```ruby
  test "original keeps its keys and formats" do
    login_as @user
    entry = @entries.first
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    get :show, params: {id: entry, include_original: "true"}, format: :json
    assert_response :success

    original = parse_json["original"]
    assert_equal %w[author content title url entry_id published data fingerprint], original.keys
    assert_equal "<p>Old text.</p>", original["content"]
    assert_equal entry.title, original["title"]
    assert_equal entry.url, original["url"]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, original["published"])
  end

  test "original is null without one" do
    login_as @user

    get :show, params: {id: @entries.first, include_original: "true"}, format: :json
    assert_response :success

    result = parse_json
    assert result.key?("original")
    assert_nil result["original"]
  end

  test "extended mode returns the same original" do
    login_as @user
    entry = @entries.first
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p>", base: entry.content))

    get :show, params: {id: entry, mode: "extended"}, format: :json
    assert_response :success

    assert_equal "<p>Old text.</p>", parse_json.dig("original", "content")
  end
```

- [ ] **Step 3: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/presenters/entry_presenter_test.rb test/controllers/api/v2/entries_controller_test.rb
```

Expected: FAIL. The presenter tests error with `NoMethodError: undefined method 'api_original'`. "original keeps its keys and formats" and "extended mode returns the same original" fail because `original` is `nil` (the templates still read the `original` column).

- [ ] **Step 4: Add `api_original`**

In `app/presenters/entry_presenter.rb`, add this method directly after the `api_content` method:

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

- [ ] **Step 5: Change the two templates**

In `app/views/api/v2/entries/_entry_default.json.jbuilder`, replace:

```ruby
  json.original entry.original if params[:include_original] == "true"
```

with:

```ruby
  json.original entry_presenter.api_original if params[:include_original] == "true"
```

In `app/views/api/v2/entries/_entry_extended.json.jbuilder`, replace:

```ruby
  json.original entry.original
```

with:

```ruby
  json.original entry_presenter.api_original
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/presenters/entry_presenter_test.rb test/controllers/api/v2/entries_controller_test.rb
```

Expected: PASS, 0 failures. This includes the existing "should show entry with all keys" test.

- [ ] **Step 7: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/presenters/entry_presenter.rb test/presenters/entry_presenter_test.rb test/controllers/api/v2/entries_controller_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 8: Commit**

```bash
source ~/.bash_profile && git add app/presenters/entry_presenter.rb app/views/api/v2/entries/_entry_default.json.jbuilder app/views/api/v2/entries/_entry_extended.json.jbuilder test/presenters/entry_presenter_test.rb test/controllers/api/v2/entries_controller_test.rb && git commit -m "API v2 builds original from the current columns and the compressed original content"
```

---

### Task 5: Ignore `original`, add the backfill job, then the Deploy 1 checks

After Tasks 2–4, no code reads or writes `original`. This task makes `Entry` stop loading it and adds the only code that still uses it: the backfill.

**Files:**
- Modify: `app/models/entry.rb` (add `ignored_columns` near the top of the class)
- Modify: `test/models/entry_test.rb`
- Modify: `test/jobs/feed_crawler/entry_update_test.rb`
- Create: `app/jobs/backfill_original_content.rb`
- Create: `test/jobs/backfill_original_content_test.rb`

**Interfaces:**
- Consumes: `OriginalContent.compress(original, base:)` (Task 1). `Entry#original_content` and the `compressed_original_content` column (Task 2). The `EntryUpdate` behavior from Task 3.
- Produces:
  - `Entry.ignored_columns` includes `"original"`.
  - `BackfillOriginalContent::BATCH_SIZE` = `100_000`.
  - `BackfillOriginalContent#perform(batch)`: converts every row with an `original` in IDs `(batch - 1) * BATCH_SIZE + 1` to `batch * BATCH_SIZE`.
  - `BackfillOriginalContent#convert(entry)`: one row. `entry` must have `id`, `content`, `original`, and `updated_at` loaded with an explicit `select`.
  - `BackfillOriginalContent#build`: queues `[N]` down to `[1]`, where `N` is `ceil(Entry.maximum(:id) / BATCH_SIZE)`.

- [ ] **Step 1: Write the failing tests for the ignore**

In `test/models/entry_test.rb`, add this test before the `private` line:

```ruby
  test "Entry does not load the legacy original column" do
    refute_includes Entry.column_names, "original"
  end
```

In `test/jobs/feed_crawler/entry_update_test.rb`, add this test before the `private` line:

```ruby
    test "significant change on an unconverted entry writes a temporary original" do
      Entry.where(id: @entry.id).update_all(original: {"content" => "<p>Legacy original.</p>"}.to_json)

      EntryUpdate.create!(update_data(significant(@old_content)), @entry.reload)

      assert_equal @old_content, @entry.reload.original_content
      assert_equal({"content" => "<p>Legacy original.</p>"}, Entry.where(id: @entry.id).pick(:original))
    end
```

- [ ] **Step 2: Write the failing backfill tests**

Create `test/jobs/backfill_original_content_test.rb`:

```ruby
require "test_helper"

class BackfillOriginalContentTest < ActiveSupport::TestCase
  setup do
    @feed = users(:ben).feeds.first
  end

  test "perform converts the legacy original and clears it" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "perform replaces a temporary original with the legacy value" do
    content = "<p>Old text.</p><p>Newer text.</p><p>Newest text.</p>"
    entry = entry_with_legacy_original(content: content, original_content: "<p>Old text.</p>")
    entry.update!(compressed_original_content: OriginalContent.compress("<p>Old text.</p><p>Newer text.</p>", base: content))

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_equal "<p>Old text.</p>", entry.reload.original_content
  end

  test "perform does not change updated_at" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    updated_at = entry.updated_at

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_equal updated_at, entry.reload.updated_at
  end

  test "perform clears both columns for a blank original" do
    entry = entry_with_legacy_original(content: "<p>New text.</p>", original_content: "")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_nil entry.reload.compressed_original_content
  end

  test "perform clears both columns for blank current content" do
    entry = entry_with_legacy_original(content: "<p>New text.</p>", original_content: "<p>Old text.</p>")
    entry.update_columns(content: "")

    BackfillOriginalContent.new.perform(batch_for(entry))

    assert_nil legacy_original(entry)
    assert_nil entry.reload.compressed_original_content
  end

  test "perform a second time keeps the converted value" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    job = BackfillOriginalContent.new
    job.perform(batch_for(entry))
    blob = entry.reload.compressed_original_content

    job.perform(batch_for(entry))

    assert_equal blob, entry.reload.compressed_original_content
    assert_equal "<p>Old text.</p>", entry.original_content
  end

  test "convert leaves a row alone when updated_at changed after the read" do
    entry = entry_with_legacy_original(content: "<p>Old text.</p><p>New text.</p>", original_content: "<p>Old text.</p>")
    stale = Entry.select(:id, :content, :original, :updated_at).find(entry.id)
    entry.update_columns(updated_at: entry.updated_at + 1.second)

    BackfillOriginalContent.new.convert(stale)

    assert_equal "<p>Old text.</p>", legacy_original(entry)["content"]
    assert_nil entry.reload.compressed_original_content
  end

  test "build queues one job for each range, newest range first" do
    BackfillOriginalContent.jobs.clear
    entry_with_legacy_original(content: "<p>New text.</p>", original_content: "<p>Old text.</p>")
    batches = (Entry.maximum(:id) / BackfillOriginalContent::BATCH_SIZE.to_f).ceil

    BackfillOriginalContent.new.build

    assert_equal batches, BackfillOriginalContent.jobs.size
    assert_equal [batches], BackfillOriginalContent.jobs.first["args"]
    assert_equal [1], BackfillOriginalContent.jobs.last["args"]
  end

  private

  def entry_with_legacy_original(content:, original_content:)
    entry = @feed.entries.create!(public_id: SecureRandom.hex, content: content)
    Entry.where(id: entry.id)
      .update_all(original: {"author" => "Author", "content" => original_content, "title" => "Title"}.to_json)
    entry.reload
  end

  def legacy_original(entry)
    Entry.where(id: entry.id).pick(:original)
  end

  def batch_for(entry)
    (entry.id - 1) / BackfillOriginalContent::BATCH_SIZE + 1
  end
end
```

Each `updated_at` comparison uses values that came back from the database. An in-memory `Time` has nanoseconds on Linux CI but the database keeps microseconds, so never compare against a value that did not round-trip.

- [ ] **Step 3: Run the tests to see them fail**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/backfill_original_content_test.rb
```

Expected: FAIL.
- "Entry does not load the legacy original column" fails, because `Entry.column_names` includes `"original"`.
- "significant change on an unconverted entry writes a temporary original" fails, because the JSON string is stored as a JSON string literal while the column is not ignored, so `pick(:original)` does not return the hash.
- The backfill tests error with `NameError: uninitialized constant BackfillOriginalContentTest::BackfillOriginalContent`.

- [ ] **Step 4: Ignore the column**

In `app/models/entry.rb`, directly after the `store :settings, ...` line near the top of the class, add:

```ruby
  # Deploy 1 stops loading the legacy column. BackfillOriginalContent still
  # reads it by name. Deploy 2 drops the column and removes this line.
  self.ignored_columns += ["original"]
```

- [ ] **Step 5: Write the job**

Create `app/jobs/backfill_original_content.rb`:

```ruby
# Moves each legacy original value into compressed_original_content and
# clears the legacy column. One job for each range of ids: production ids are sparse
# (about 2.6% in use), so the range is larger than SidekiqHelper::BATCH_SIZE.
# Entry ignores the original column, so this job selects it by name.
class BackfillOriginalContent
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000

  def perform(batch)
    first = (batch - 1) * BATCH_SIZE + 1
    Entry.where(id: first..(first + BATCH_SIZE - 1)).where.not(original: nil)
      .select(:id, :content, :original, :updated_at)
      .find_each(batch_size: 500) { |entry| convert(entry) }
  end

  # The updated_at condition skips a row the crawler changed after the read.
  # That row keeps its legacy original, and a second build converts it. The
  # legacy value replaces any temporary original EntryUpdate wrote meanwhile.
  # update_all skips callbacks and leaves updated_at as it is.
  def convert(entry)
    compressed = OriginalContent.compress(entry.original&.dig("content"), base: entry.content)
    Entry.where(id: entry.id, updated_at: entry.updated_at)
      .update_all(compressed_original_content: compressed, original: nil)
  end

  # Newest ranges first: recently updated entries are the ones people read.
  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq::Client.push_bulk(
      "args" => batches.downto(1).map { [_1] },
      "class" => self.class
    )
  end
end
```

- [ ] **Step 6: Run the tests to see them pass**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/backfill_original_content_test.rb
```

Expected: PASS, 0 failures.

- [ ] **Step 7: Lint**

```bash
source ~/.bash_profile && bundle exec standardrb --cache false app/models/entry.rb app/jobs/backfill_original_content.rb test/models/entry_test.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/backfill_original_content_test.rb
```

Expected: no new offenses compared with `HEAD`.

- [ ] **Step 8: Commit**

```bash
source ~/.bash_profile && git add app/models/entry.rb app/jobs/backfill_original_content.rb test/models/entry_test.rb test/jobs/feed_crawler/entry_update_test.rb test/jobs/backfill_original_content_test.rb && git commit -m "Ignore entries.original and add BackfillOriginalContent to convert it"
```

- [ ] **Step 9: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: 0 failures, 0 errors. If the run fails, read the RTK tee log for the details.

- [ ] **Step 10: Check that only the backfill uses `original`**

```bash
source ~/.bash_profile && git grep -nP '\.original(?![-\w])|\boriginal:\s|\["original"\]|\boriginal\[' -- app lib
```

Expected: exactly these hits.

- `app/views/api/v2/entries/_entry_default.json.jbuilder` and `app/views/api/v2/entries/_entry_extended.json.jbuilder`: `json.original entry_presenter.api_original`. These lines write the API key, not the column.
- `app/jobs/backfill_original_content.rb`: `entry.original&.dig("content")` and `original: nil`.

Any other hit that reads or writes the `original` column must change before Deploy 1.

---

## Backfill (after Deploy 1)

Ben runs these steps from `docs/ops/original-content-compression-runbook.html`. They are not code changes. In short:

1. Run `BackfillOriginalContent.new.build`. It queues about 54,000 jobs, newest range first.
2. When the queue is empty, run `build` again for the rows that changed during the first run.
3. When the queue is empty again, check that `Entry.where.not(original: nil).count` is `0`.

---

## Deploy 2 (after the backfill shows 0 legacy rows)

### Task 6: Drop `original` and remove the backfill

**Files:**
- Create: `db/migrate/20261003130000_remove_original_from_entries.rb`
- Modify: `db/structure.sql` (generated)
- Modify: `app/models/entry.rb` (remove the `ignored_columns` lines from Task 5)
- Modify: `test/models/entry_test.rb` (delete the ignore test)
- Modify: `test/jobs/feed_crawler/entry_update_test.rb` (delete the unconverted-entry test)
- Delete: `app/jobs/backfill_original_content.rb`
- Delete: `test/jobs/backfill_original_content_test.rb`

**Interfaces:**
- Consumes: Deploy 1 is live, so the running code ignores `original`. The backfill shows 0 legacy rows.
- Produces: `entries` has no `original` column, and no code refers to it.

- [ ] **Step 1: Write the migration**

Create `db/migrate/20261003130000_remove_original_from_entries.rb`:

```ruby
class RemoveOriginalFromEntries < ActiveRecord::Migration[8.1]
  def change
    safety_assured { remove_column :entries, :original, :json }
  end
end
```

strong_migrations blocks `remove_column` until the running code ignores the column. Deploy 1 did that, so `safety_assured` is correct here. On Postgres, `DROP COLUMN` changes only the catalog. It needs a short `ACCESS EXCLUSIVE` lock, and strong_migrations sets `lock_timeout` to 10 seconds.

- [ ] **Step 2: Run the migration on the dev database**

```bash
source ~/.bash_profile && bin/rails db:migrate
```

```bash
source ~/.bash_profile && git diff db/structure.sql
```

Expected: the line `original json,` is removed from `CREATE TABLE public.entries`, and `('20261003130000')` is added to the `schema_migrations` insert. Keep only these two hunks.

- [ ] **Step 3: Remove the ignore and the tests for the legacy column**

In `app/models/entry.rb`, delete these three lines:

```ruby
  # Deploy 1 stops loading the legacy column. BackfillOriginalContent still
  # reads it by name. Deploy 2 drops the column and removes this line.
  self.ignored_columns += ["original"]
```

The migration runs before the new code starts, so the new code never sees the column.

In `test/models/entry_test.rb`, delete the whole `test "Entry does not load the legacy original column"` block.

In `test/jobs/feed_crawler/entry_update_test.rb`, delete the whole `test "significant change on an unconverted entry writes a temporary original"` block.

- [ ] **Step 4: Delete the backfill job and its test**

```bash
source ~/.bash_profile && git rm app/jobs/backfill_original_content.rb test/jobs/backfill_original_content_test.rb
```

- [ ] **Step 5: Check for other uses of the column**

```bash
source ~/.bash_profile && git grep -nP '\.original(?![-\w])|\boriginal:\s|\["original"\]|\boriginal\[' -- app lib test
```

Expected: exactly these three hits.

- `app/views/api/v2/entries/_entry_default.json.jbuilder` and `app/views/api/v2/entries/_entry_extended.json.jbuilder`: `json.original entry_presenter.api_original`. These lines write the API key, not the column.
- `test/controllers/settings/billings_controller_test.rb:50`: `original: plans(:basic_monthly_3)`. This is a billing plan, not the column.

Any other hit that reads or writes the `original` column must change before you continue.

- [ ] **Step 6: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
source ~/.bash_profile && git add -A db/migrate/20261003130000_remove_original_from_entries.rb db/structure.sql app/models/entry.rb test/models/entry_test.rb test/jobs/feed_crawler/entry_update_test.rb && git commit -m "Drop entries.original and remove the finished backfill"
```

