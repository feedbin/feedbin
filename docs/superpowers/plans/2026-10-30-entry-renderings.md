# Entry Renderings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store each entry's formatted output (web, api, full, diff) once in a side table, serve it verbatim, fill it eagerly on write and lazily on read, and rebuild it by hand with Sidekiq.

**Architecture:** A new table `entry_renderings (entry_id, version, blob)` holds one zstd frame per entry, dictionary-compressed against `entries.content`, behind a 5-byte header (layout byte + CRC32 of the inputs). `EntryRendering` encodes, decodes and renders; `Entry#rendering` returns the stored row when its version and CRC match, otherwise renders, upserts and returns a fresh one. An `after_commit` on `Entry` keeps it current for the crawler, `EntryUpdate` and every other writer. `RenderingsRebuild` is a Sidekiq job over id ranges or id lists that writes into either the live table or a fresh one, with `rails renderings:*` tasks to start, watch and swap.

**Tech Stack:** Rails 8.1, Postgres 11, Sidekiq (`backfill` queue), `zstd-ruby`, `Zlib.crc32`, `HTMLDiff` (feedbin/html_diff), html-pipeline fork at `~/Sites/html-pipeline` (branch `feedbin`).

**Spec:** `/Users/ben/Sites/feedbin-api-docs/design.md`, the Decisions rows dated 2026-10-30 (blob layout, versions, `entry_renderings`, `VERSION`, eager diff, api camo, manual rebuild) and the "Rebuilding stored content" and "WAL and disk cost" measurements.

## Global Constraints

- Run every shell command after `source ~/.bash_profile`. Feedbin tests: `rails test` (about 13 s; over a minute means stuck, never run two suites at once). Fork tests: `cd ~/Sites/html-pipeline && LANG=en_US.UTF-8 bundle exec rake`.
- Branch: `content_formatter` in `~/Sites/feedbin`. Commit after each task. No `Co-Authored-By` line in commit messages.
- Never commit `newsletter.html` or `user5_entries.jsonl.gz`.
- `api` output must not change except for the one added attribute `data-camo-src` (spec: "v2 output gains one attribute and nothing else changes"). `web` output does not change at all.
- Rendering depends on the entry alone: no user, no request, no time.
- Blob layout (spec): byte 0 = layout version `1`; bytes 1–4 = CRC32 big-endian of the inputs; the rest = one zstd frame, `level: 3`, dictionary = `entries.content`.
- Stored versions: `web` and `api` always; `full` only when `entry.feed.newsletter?`; `diff` only when there is an original whose length differs from `content` (the rule `Entry#content_diff` uses today).
- One `ContentFormatter::VERSION` (integer). A stored row with another version, or a CRC that does not match, is treated as missing: render, store, serve.
- A rendering failure must never fail an entry write or a page: the callback rescues and reports through `ErrorService.notify`; readers that raise fall back the way `EntryPresenter#content` does today.
- Full rebuild = fresh table `entry_renderings_new` then a rename swap; scoped rebuild (`FEED=`, `SINCE=`) = upsert in place. Jobs run on the `backfill` queue.

## Review Focus

1. **An entry with blank content.** Both `web` and `api` are `""`; the blob is stored with no dictionary and reads back without raising. Test in Task 4.
2. **Content changed without callbacks** (`update_columns`, `update_multiple`, direct SQL). The stored CRC no longer matches, so the reader must re-render rather than decompress against the wrong dictionary and return garbage or raise. Test in Task 5.
3. **A formatter exception during `after_commit`.** The entry must still be created and the error reported; the next read renders live. Test in Task 5.
4. **A scoped rebuild over rows that are already current.** It must skip them (no write) and still count them, and an entry deleted between enqueue and perform must not fail the job. Test in Task 7.
5. **Swapping while jobs are still out, or after new entries arrived during the rebuild.** `swap` refuses while `pending > 0`, and rows written to the live table at the current `VERSION` during the rebuild are copied into the new table before the rename. Test in Task 8.

---

### Task 1: `api` keeps `src` and adds `data-camo-src`

The fork's `CamoFilter` replaces `src`, `poster` and `srcset`. The `api` rendering needs the originals left in place with `data-camo-*` added beside them, and no `data-canonical-*` (it would duplicate the attribute that stayed).

**Files:**
- Modify: `~/Sites/html-pipeline/lib/html/pipeline/camo_filter.rb`
- Test: `~/Sites/html-pipeline/test/html/pipeline/camo_filter_test.rb`
- Modify: `~/Sites/feedbin/app/models/content_formatter.rb` (`Api#filters`, `Api#context`)
- Modify: `~/Sites/feedbin/Gemfile.lock` (html-pipeline revision)
- Modify: `~/Sites/feedbin/app/helpers/entries_helper.rb:13` (`"v2"` → `"v3"`)
- Test: `~/Sites/feedbin/test/models/content_formatter_test.rb`

**Interfaces:**
- Produces: `CamoFilter` context option `:asset_keep_src` (boolean). When true, `src`, `poster` and `srcset` are left untouched and only `data-camo-src`, `data-camo-poster`, `data-camo-srcset` are added. `:asset_src_attribute` still names the attribute for `src`.
- Produces: `ContentFormatter::Api` output with `data-camo-src` on every proxied image when `CAMO_HOST`/`CAMO_KEY` are set.

- [ ] **Step 1: Write the failing fork test**

In `camo_filter_test.rb`, with the existing `@options`:

```ruby
def test_keep_src_adds_camo_attributes_beside_the_originals
  options = @options.merge(asset_src_attribute: "data-camo-src", asset_keep_src: true)
  orig = %(<p><img src="http://kottke.org/img.png" srcset="http://example.com/img.png 1w"><video poster="http://twitter.com/img.png"></video></p>)
  html = CamoFilter.call(orig, options).to_s
  assert_includes html, %(src="http://kottke.org/img.png")
  assert_includes html, %(srcset="http://example.com/img.png 1w")
  assert_includes html, %(poster="http://twitter.com/img.png")
  assert_match %r{data-camo-src="https//assets.example.org/\h{40}/\h+"}, html
  assert_match %r{data-camo-srcset="https//assets.example.org/\h{40}/\h+ 1w"}, html
  assert_match %r{data-camo-poster="https//assets.example.org/\h{40}/\h+"}, html
  refute_includes html, "data-canonical-"
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Sites/html-pipeline && LANG=en_US.UTF-8 bundle exec ruby -Ilib -Itest test/html/pipeline/camo_filter_test.rb -n test_keep_src_adds_camo_attributes_beside_the_originals`
Expected: FAIL on the `src=` assertion (src was deleted).

- [ ] **Step 3: Implement `keep_src?` in `CamoFilter`**

Add `def keep_src? = !!context[:asset_keep_src]`. In each of the three loops: delete the original attribute and write the `data-canonical-*` attribute only when `!keep_src?`; always write the `data-camo-*` attribute (for `img`, the attribute named by `src_attribute`).

- [ ] **Step 4: Run the fork suite**

Run: `cd ~/Sites/html-pipeline && LANG=en_US.UTF-8 bundle exec rake`
Expected: 123 runs, 0 failures.

- [ ] **Step 5: Commit and push the fork**

```bash
cd ~/Sites/html-pipeline && git add lib/html/pipeline/camo_filter.rb test/html/pipeline/camo_filter_test.rb && git commit -m "Add asset_keep_src to CamoFilter" && git push origin feedbin
```

- [ ] **Step 6: Write the failing Feedbin test**

In `test/models/content_formatter_test.rb`, next to "newsletter_format applies camo proxying when configured":

```ruby
test "api_format keeps src and adds data-camo-src" do
  with_env("CAMO_HOST" => "https://example.com", "CAMO_KEY" => "secret") do
    result = ContentFormatter.api_format(%(<img src="http://kottke.org/img.png">), @entry)
    assert_includes result, %(src="http://kottke.org/img.png")
    assert_match %r{data-camo-src="https://example.com/\h{40}/\h+"}, result
    refute_includes result, "data-canonical-src"
  end
end

test "api_format output is unchanged without camo" do
  assert_equal %(<img src="http://kottke.org/img.png">), ContentFormatter.api_format(%(<img src="http://kottke.org/img.png">), @entry)
end
```

- [ ] **Step 7: Run it to verify it fails**

Run: `rails test test/models/content_formatter_test.rb`
Expected: the first new test FAILS (no `data-camo-src`).

- [ ] **Step 8: Bump the lockfile and add the filter**

```bash
cd ~/Sites/feedbin && bundle lock --update html-pipeline
```
Check `git diff Gemfile.lock` touches only the html-pipeline revision (revert any other gem that moved, as `json` did last time).

In `ContentFormatter::Api`: append `(HTML::Pipeline::CamoFilter if camo?)` to `filters` (then `.compact`), and merge `camo_context.merge(asset_keep_src: true)` into `context` (only when `camo?`, so `url_context.merge(scrub_mode: ...)` stays identical without camo).

Change `EntriesHelper.api_entries_cache_key`'s `"v2"` to `"v3"`.

- [ ] **Step 9: Run the suite**

Run: `rails test`
Expected: 0 failures.

- [ ] **Step 10: Commit**

```bash
git add Gemfile.lock app/models/content_formatter.rb app/helpers/entries_helper.rb test/models/content_formatter_test.rb
git commit -m "Proxy api images with data-camo-src beside src"
```

---

### Task 2: `Full` absorbs the media-query rewrite

`EntryPresenter#update_media_queries` is an input transform for the newsletter's full version. It moves into the format so the stored `full` is complete.

**Files:**
- Modify: `app/models/content_formatter.rb` (`Full`)
- Modify: `app/presenters/entry_presenter.rb:97-116` (delete `is_numeric?`, `update_media_queries`; `newsletter_content` calls `ContentFormatter.newsletter_format(formatted_content)` for now)
- Test: `test/models/content_formatter_test.rb`

**Interfaces:**
- Produces: `ContentFormatter::Full.media_queries(html) -> String`, applied inside `Full#call` before the pipeline. Same regex and rule as today: a `max-width` of 400 px or more becomes 10,000 px; a non-numeric width is left alone; a rescue returns the input.

- [ ] **Step 1: Write the failing tests**

```ruby
test "newsletter_format widens max-width media queries of 400px and up" do
  input = "<style>@media screen and (max-width:480px) { .a {} } @media (max-width:320px) { .b {} }</style><p>x</p>"
  result = ContentFormatter.newsletter_format(input)
  assert_includes result, "(max-width:10000px)"
  assert_includes result, "(max-width:320px)"
end

test "Full.media_queries leaves a non-numeric width alone" do
  assert_equal "@media (max-width:abcpx) {", ContentFormatter::Full.media_queries("@media (max-width:abcpx) {")
end
```

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/models/content_formatter_test.rb`
Expected: FAIL, `10000px` absent / `media_queries` undefined.

- [ ] **Step 3: Move the method**

Define `def self.media_queries(html)` on `ContentFormatter::Full` with the presenter's body (`is_numeric?` inlined as `string.strip.to_i.to_s == string.strip`). Override `Full#call(content)` to `super(self.class.media_queries(content))`. Delete the two presenter methods and the call in `newsletter_content`.

- [ ] **Step 4: Run the suite**

Run: `rails test`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/content_formatter.rb app/presenters/entry_presenter.rb test/models/content_formatter_test.rb
git commit -m "Move the newsletter media-query rewrite into ContentFormatter::Full"
```

---

### Task 3: `ContentFormatter::VERSION` and the fingerprint test

**Files:**
- Modify: `app/models/content_formatter.rb`
- Create: `lib/tasks/renderings.rake`
- Create: `test/fixtures/files/content_formatter_fingerprint.txt`
- Test: `test/models/content_formatter_test.rb`

**Interfaces:**
- Produces: `ContentFormatter::VERSION = 1` (Integer).
- Produces: `ContentFormatter.fingerprint -> String` (64 hex chars): SHA256 over, in this order, the bytes of `app/models/content_formatter.rb`, each `app/models/content_filters/*.rb` sorted by path, `app/models/entry_rendering.rb` if it exists, then one line per gem for `html-pipeline`, `html_diff`, `sanitize`, `nokogiri`, `loofah`, `zstd-ruby`: `"#{name} #{version} #{git revision or ''}"`, read from `Bundler.locked_gems.specs` (`spec.source.revision` when the source responds to it).
- Produces: rake `renderings:fingerprint`, which writes `"#{VERSION} #{fingerprint}\n"` to the fixture file.

- [ ] **Step 1: Write the failing test**

```ruby
test "VERSION is bumped when the formatter or its gems change" do
  stored_version, stored_digest = file_fixture("content_formatter_fingerprint.txt").read.split
  message = if stored_digest != ContentFormatter.fingerprint && stored_version == ContentFormatter::VERSION.to_s
    "ContentFormatter's output inputs changed. Bump ContentFormatter::VERSION, then run `rails renderings:fingerprint`."
  else
    "Run `rails renderings:fingerprint` to record the current VERSION and fingerprint."
  end
  assert_equal [ContentFormatter::VERSION.to_s, ContentFormatter.fingerprint], [stored_version, stored_digest], message
end
```

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/models/content_formatter_test.rb`
Expected: FAIL, fixture missing / `VERSION` uninitialized.

- [ ] **Step 3: Implement `VERSION`, `fingerprint` and the rake task**

`lib/tasks/renderings.rake`:

```ruby
namespace :renderings do
  desc "Record ContentFormatter::VERSION and its fingerprint for the test suite"
  task fingerprint: :environment do
    path = Rails.root.join("test/fixtures/files/content_formatter_fingerprint.txt")
    File.write(path, "#{ContentFormatter::VERSION} #{ContentFormatter.fingerprint}\n")
    puts File.read(path)
  end
end
```

- [ ] **Step 4: Generate the fixture and run the suite**

Run: `rails renderings:fingerprint && rails test`
Expected: the fixture holds `1 <digest>`; 0 failures.

- [ ] **Step 5: Prove the test bites**

Add a blank line to `app/models/content_filters/scrub.rb`, run `rails test test/models/content_formatter_test.rb`, expect the "Bump ContentFormatter::VERSION" failure, then revert the blank line.

- [ ] **Step 6: Commit**

```bash
git add app/models/content_formatter.rb lib/tasks/renderings.rake test/fixtures/files/content_formatter_fingerprint.txt test/models/content_formatter_test.rb
git commit -m "Add ContentFormatter::VERSION with a fingerprint test"
```

---

### Task 4: `entry_renderings` table and `EntryRendering`

**Files:**
- Create: `db/migrate/20261030120000_create_entry_renderings.rb`
- Modify: `db/structure.sql` (generated)
- Create: `app/models/entry_rendering.rb`
- Test: `test/models/entry_rendering_test.rb`

**Interfaces:**
- Produces the table: `entry_renderings (entry_id bigint PRIMARY KEY, version smallint NOT NULL, blob bytea NOT NULL)`, `blob` with `STORAGE EXTERNAL`, no foreign key (Task 5 deletes rows explicitly; the swap in Task 8 would otherwise have to recreate the constraint).
- Produces `EntryRendering < ApplicationRecord`, `self.primary_key = :entry_id`, `belongs_to :entry`:
  - `LAYOUT = 1`, `VERSIONS = %i[web api full diff].freeze`
  - `self.source_html(entry, html = entry.content) -> String`: `ContentFormatter.text_email(html)` when `entry.content_format == "text"`; the YouTube iframe (`<iframe src="https://www.youtube.com/embed/#{id}?rel=0&amp;showinfo=0" frameborder="0" allowfullscreen="allowfullscreen" width="1280" height="720"></iframe>`) followed by `ContentFormatter.text_email(html)` when `entry.data&.dig("youtube_video_id").present?`; otherwise `html.to_s`. (This is `EntryPresenter#formatted_content` moved off the template.)
  - `self.versions_for(entry) -> Hash{Symbol => String|nil}`: `web = ContentFormatter.render(:web, source, entry: entry)`, `api = ContentFormatter.render(:api, source, entry: entry)`, `full = ContentFormatter.render(:full, entry.content.to_s, entry: entry)` only when `entry.feed.newsletter?` else nil, `diff` = `HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{web}</div>").inline_html` where `before = ContentFormatter.render(:web, source_html(entry, original), entry: entry)`, only when `original = entry.original_content` is present and `original.length != entry.content.length`, else nil.
  - `self.inputs_crc(entry) -> Integer`: `Zlib.crc32(entry.compressed_original_content.to_s, Zlib.crc32(entry.content.to_s))`.
  - `self.encode(versions, content:, crc:) -> String` (binary): `[LAYOUT, crc].pack("CN") + Zstd.compress(payload, level: 3, **dict)` where `payload = VERSIONS.map { versions[_1].to_s.b }.pack("N/a*N/a*N/a*N/a*")` and `dict` is `{dict: content}` when `content.present?`, else `{}`.
  - `self.decode(blob, content:) -> Hash{Symbol => String|nil}`: inverse; raises `ArgumentError` on a layout byte other than `LAYOUT`; strings forced to UTF-8; `full` and `diff` become nil when empty.
  - `self.build(entry) -> EntryRendering` (unsaved): `entry_id`, `version: ContentFormatter::VERSION`, `blob: encode(versions_for(entry), content: entry.content, crc: inputs_crc(entry))`.
  - `self.render!(entry) -> EntryRendering`: `build`, then `upsert({entry_id:, version:, blob:}, unique_by: :entry_id)`, returns the built record.
  - `#layout -> Integer`, `#crc -> Integer` (from the header), `#current_for?(entry) -> Boolean`: `layout == LAYOUT && version == ContentFormatter::VERSION && crc == self.class.inputs_crc(entry)`.
  - `#web`, `#api`, `#full`, `#diff -> String|nil`: from `decode(blob, content: entry.content)`, memoized.

- [ ] **Step 1: Write the migration and run it**

```ruby
class CreateEntryRenderings < ActiveRecord::Migration[8.1]
  def up
    create_table :entry_renderings, id: false do |t|
      t.bigint :entry_id, null: false
      t.integer :version, null: false, limit: 2
      t.binary :blob, null: false
    end
    execute "ALTER TABLE entry_renderings ADD PRIMARY KEY (entry_id)"
    execute "ALTER TABLE entry_renderings ALTER COLUMN blob SET STORAGE EXTERNAL"
  end

  def down
    drop_table :entry_renderings
  end
end
```

Run: `rails db:migrate && RAILS_ENV=test rails db:migrate`
Expected: `db/structure.sql` gains the table with `entry_renderings_pkey`.

- [ ] **Step 2: Write the failing tests**

`test/models/entry_rendering_test.rb` (use `create_entry(feed)` from `FactoryHelper` with the `daring_fireball` fixture feed, and `OriginalContent.compress` for an original). Define in the test class:

```ruby
def newsletter_feed
  feeds(:kottke).tap { it.update!(feed_type: :newsletter) }
end
```

```ruby
test "encode and decode round-trip all four versions" do
  versions = {web: "<p>w</p>", api: "<p>a</p>", full: "<html>f</html>", diff: "<p><ins>d</ins></p>"}
  blob = EntryRendering.encode(versions, content: "<p>w</p>", crc: 7)
  assert_equal 1, blob.getbyte(0)
  assert_equal 7, blob.byteslice(1, 4).unpack1("N")
  assert_equal versions, EntryRendering.decode(blob, content: "<p>w</p>")
end

test "decode returns nil for an absent full and diff" do
  blob = EntryRendering.encode({web: "<p>w</p>", api: "<p>a</p>"}, content: "<p>w</p>", crc: 0)
  decoded = EntryRendering.decode(blob, content: "<p>w</p>")
  assert_nil decoded[:full]
  assert_nil decoded[:diff]
  assert_equal Encoding::UTF_8, decoded[:web].encoding
end

test "encode works without a dictionary when content is blank" do
  blob = EntryRendering.encode({web: "", api: ""}, content: "", crc: 0)
  assert_equal "", EntryRendering.decode(blob, content: "")[:web]
end

test "decode rejects an unknown layout" do
  assert_raises(ArgumentError) { EntryRendering.decode("\x02\x00\x00\x00\x00".b, content: "x") }
end

test "build renders web and api, and full only for newsletters" do
  entry = create_entry(feeds(:daring_fireball))  # any non-newsletter fixture feed
  rendering = EntryRendering.build(entry)
  assert_equal ContentFormatter.format!(entry.content, entry), rendering.web
  assert_equal ContentFormatter.api_format(entry.content, entry), rendering.api
  assert_nil rendering.full
  assert_nil rendering.diff
  assert_equal ContentFormatter::VERSION, rendering.version
end

test "build renders a diff when the original differs in length" do
  entry = create_entry(feeds(:daring_fireball))
  entry.update!(content: "<p>This is the new text.</p>", compressed_original_content: OriginalContent.compress("<p>This is the text.</p>", base: "<p>This is the new text.</p>"))
  assert_match %r{<ins>new\s*</ins>}, EntryRendering.build(entry).diff
end

test "build renders full for a newsletter entry" do
  entry = create_entry(newsletter_feed)  # a feed with feed_type: :newsletter; add a helper if the fixtures have none
  entry.update!(content: "<html><body><style>@media (max-width:480px){}</style><p>n</p></body></html>")
  assert_includes EntryRendering.build(entry).full, "max-width:10000px"
end

test "source_html wraps text entries and youtube entries" do
  entry = create_entry(feeds(:daring_fireball))
  entry.content_format = "text"
  entry.content = "line one\nline two"
  assert_equal ContentFormatter.text_email(entry.content), EntryRendering.source_html(entry)
  entry.content_format = nil
  entry.data = {"youtube_video_id" => "abc"}
  assert_includes EntryRendering.source_html(entry), %(src="https://www.youtube.com/embed/abc?rel=0&amp;showinfo=0")
end

test "render! upserts and current_for? tracks the inputs" do
  entry = create_entry(feeds(:daring_fireball))
  rendering = EntryRendering.render!(entry)
  assert rendering.current_for?(entry)
  assert_equal 1, EntryRendering.where(entry_id: entry.id).count
  EntryRendering.render!(entry)
  assert_equal 1, EntryRendering.where(entry_id: entry.id).count
  entry.content = "<p>changed</p>"
  refute EntryRendering.find(entry.id).current_for?(entry)
end

test "current_for? is false for another VERSION" do
  entry = create_entry(feeds(:daring_fireball))
  rendering = EntryRendering.render!(entry)
  rendering.version = ContentFormatter::VERSION + 1
  refute rendering.current_for?(entry)
end
```

- [ ] **Step 3: Run to verify failure**

Run: `rails test test/models/entry_rendering_test.rb`
Expected: FAIL, `EntryRendering` uninitialized.

- [ ] **Step 4: Implement `app/models/entry_rendering.rb`** per the Interfaces block. `upsert` with `unique_by: :entry_id` and `on_duplicate: :update` (the default) covers both insert and overwrite.

- [ ] **Step 5: Run the file, then the suite**

Run: `rails test test/models/entry_rendering_test.rb && rails test`
Expected: 0 failures. The fingerprint test fails because `entry_rendering.rb` now exists: run `rails renderings:fingerprint` (no `VERSION` bump: nothing is stored yet) and rerun.

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/structure.sql app/models/entry_rendering.rb test/models/entry_rendering_test.rb test/fixtures/files/content_formatter_fingerprint.txt
git commit -m "Add entry_renderings and EntryRendering"
```

---

### Task 5: `Entry#rendering`, eager fill, deletion

**Files:**
- Modify: `app/models/entry.rb` (associations, callbacks, `content_diff`, `for_api`)
- Modify: `app/jobs/entry_deleter.rb:99-105`
- Test: `test/models/entry_test.rb`

**Interfaces:**
- Produces: `Entry has_one :rendering_record, class_name: "EntryRendering", dependent: :delete` (the association is the row; `rendering` is the always-current view of it).
- Produces: `Entry#rendering -> EntryRendering`: for an unsaved entry `EntryRendering.build(self)`; otherwise `rendering_record` when `rendering_record&.current_for?(self)`, else `EntryRendering.render!(self)`. Memoized in `@rendering`.
- Produces: `Entry::RENDERING_INPUTS = %w[content compressed_original_content url data settings content_format].freeze` and `after_commit :store_rendering, on: [:create, :update]`, which runs on create always and on update only when `saved_changes.keys.intersect?(RENDERING_INPUTS)`; it calls `EntryRendering.render!(self)` and rescues `StandardError` into `ErrorService.notify(error_class: "Entry#store_rendering", error_message: ..., parameters: {entry_id: id, exception: e})`.
- Changes: `Entry#content_diff` becomes `rendering.diff&.html_safe` (memo dropped: `rendering` memoizes).
- Changes: `Entry.for_api` adds `.preload(:rendering_record)` in both branches.
- Changes: `EntryDeleter#delete_entries` adds `EntryRendering.where(entry_id: entry_ids).delete_all` inside the transaction, before `Entry.where(id: entry_ids).delete_all`.

- [ ] **Step 1: Write the failing tests** (in `test/models/entry_test.rb`, with `saved_entry`)

```ruby
test "creating an entry stores its rendering" do
  entry = saved_entry("<p>Text.</p>")
  assert EntryRendering.find(entry.id).current_for?(entry)
end

test "updating content re-renders, updating the title does not" do
  entry = saved_entry("<p>Text.</p>")
  before = EntryRendering.find(entry.id).blob
  entry.update!(title: "New title")
  assert_equal before, EntryRendering.find(entry.id).blob
  entry.update!(content: "<p>Other.</p>")
  refute_equal before, EntryRendering.find(entry.id).blob
end

test "rendering re-renders when content changed outside callbacks" do
  entry = saved_entry("<p>Text.</p>")
  entry.update_columns(content: "<p>Rewritten without callbacks.</p>")
  entry = Entry.find(entry.id)
  assert_equal ContentFormatter.format!(entry.content, entry), entry.rendering.web
  assert EntryRendering.find(entry.id).current_for?(entry)
end

test "rendering re-renders when the stored VERSION differs" do
  entry = saved_entry("<p>Text.</p>")
  EntryRendering.where(entry_id: entry.id).update_all(version: ContentFormatter::VERSION + 1)
  entry = Entry.find(entry.id)
  assert_equal "<p>Text.</p>", entry.rendering.web
  assert_equal ContentFormatter::VERSION, EntryRendering.find(entry.id).version
end

test "a rendering failure does not fail the entry write" do
  EntryRendering.stub(:render!, ->(_) { raise "boom" }) do
    entry = saved_entry("<p>Text.</p>")
    assert entry.persisted?
    assert_nil EntryRendering.find_by(entry_id: entry.id)
  end
end

test "rendering of an unsaved entry is built, not stored" do
  entry = Entry.new(content: "<p>x</p>", feed: @user.feeds.first)
  assert_equal "<p>x</p>", entry.rendering.web
  assert_equal 0, EntryRendering.count
end

test "deleting entries deletes their renderings" do
  entry = saved_entry("<p>Text.</p>")
  EntryDeleter.new.delete_entries(entry.feed_id, [entry.id])
  assert_nil EntryRendering.find_by(entry_id: entry.id)
end
```

Keep the three existing `content_diff` tests; they must pass unchanged.

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/models/entry_test.rb`
Expected: the new tests FAIL (`rendering` undefined, no rows).

- [ ] **Step 3: Implement** per the Interfaces block.

- [ ] **Step 4: Run the suite**

Run: `rails test`
Expected: 0 failures. If `ErrorService.notify` in tests raises or logs noisily, match how `OriginalContent` tests handle it.

- [ ] **Step 5: Commit**

```bash
git add app/models/entry.rb app/jobs/entry_deleter.rb test/models/entry_test.rb
git commit -m "Keep an EntryRendering current for every entry"
```

---

### Task 6: Serve the stored rendering on the web and in API v2

**Files:**
- Modify: `app/presenters/entry_presenter.rb` (`content`, `newsletter_content`, `api_content`, `app_content`; delete `formatted_content`, `text?`)
- Test: `test/presenters/entry_presenter_test.rb`

**Interfaces:**
- Changes: `EntryPresenter#content` → `entry.rendering.web` (same rescue and `&ndash;&ndash;` fallback). `#newsletter_content` → the existing `<style>` wrapper around `entry.rendering.full`. `#api_content` → `entry.rendering.api` then the micropost template wrap as today. `#app_content` → `entry.rendering.api`.
- `formatted_content` and `text?` are deleted; `youtube?` stays (other callers).

- [ ] **Step 1: Write the failing tests**

```ruby
test "content serves the stored web rendering" do
  entry = entry_with(content: "<p>live</p>")
  EntryRendering.where(entry_id: entry.id).update_all(blob: EntryRendering.encode({web: "<p>stored</p>", api: "<p>stored api</p>"}, content: entry.content, crc: EntryRendering.inputs_crc(entry)))
  presenter = presenter_for(Entry.find(entry.id))
  assert_equal "<p>stored</p>", presenter.content
  assert_equal "<p>stored api</p>", presenter.api_content
  assert_equal "<p>stored api</p>", presenter.app_content
end

test "newsletter_content wraps the stored full rendering" do
  @feed.update!(feed_type: :newsletter)
  entry = entry_with(content: "<html><body><p>n</p></body></html>")
  presenter = presenter_for(Entry.find(entry.id))
  assert_includes presenter.newsletter_content, entry.rendering.full
  assert_includes presenter.newsletter_content, "<style>"
end
```

`entry_with` and `presenter_for` are the file's existing helpers.

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/presenters/entry_presenter_test.rb`
Expected: FAIL (`content` re-renders live, not `<p>stored</p>`).

- [ ] **Step 3: Implement** per the Interfaces block.

- [ ] **Step 4: Run the suite and look at a page**

Run: `rails test`
Expected: 0 failures.

Then, in the browser pane, open `https://feedbin.resolv.app` signed in, open an article, an edited article's diff view and a newsletter's "show original"; each renders. Run `rails restart` first if the page served stale code.

- [ ] **Step 5: Commit**

```bash
git add app/presenters/entry_presenter.rb test/presenters/entry_presenter_test.rb
git commit -m "Serve stored renderings on the web and in API v2"
```

---

### Task 7: `RenderingsRebuild` job

**Files:**
- Create: `app/jobs/renderings_rebuild.rb`
- Test: `test/jobs/renderings_rebuild_test.rb`

**Interfaces:**
- Produces `RenderingsRebuild` (`include Sidekiq::Worker`, `sidekiq_options queue: :backfill`), modelled on `NewsletterBackfill`:
  - `TABLES = %w[entry_renderings entry_renderings_new].freeze`, `NEW_TABLE = "entry_renderings_new"`, `BATCH = 1_000`, `COUNTERS = %w[pending rendered skipped failed].freeze`, `TTL = 30.days.to_i`, `self.key(name) -> "renderings_rebuild:#{name}"`.
  - `self.progress -> {pending:, rendered:, skipped:, failed:}`.
  - `self.start(ids: nil, table: "entry_renderings", force: false) -> Integer` (jobs enqueued). Raises `"A pass is still running (pending: N). Pass force: true to start over."` when pending > 0 and not force. With `ids` (an Array), enqueues one job per slice of `BATCH` with selector `{"ids" => slice}`. Without `ids`, enqueues one job per id range `{"range" => [first, last]}` for `first` from 1 to `Entry.maximum(:id)` in steps of `BATCH`. Sets `pending` to the job count, zeroes the other counters, pushes with `Sidekiq::Client.push_bulk` in slices of 1,000 jobs.
  - `perform(table, selector)`: raises `ArgumentError` unless `TABLES.include?(table)`. Loads `Entry.includes(:feed).preload(:rendering_record).where(id: range or ids)`. For each entry: when `table == "entry_renderings"` and `entry.rendering_record&.current_for?(entry)`, count `skipped`; otherwise `EntryRendering.build(entry)`, count `rendered`; a `StandardError` from one entry counts `failed`, is reported via `ErrorService.notify`, and the batch continues. Writes the built rows with one statement: `INSERT INTO #{table} (entry_id, version, blob) VALUES (...), ... ON CONFLICT (entry_id) DO UPDATE SET version = EXCLUDED.version, blob = EXCLUDED.blob`, bytea literals via `connection.escape_bytea` (`connection.quote` fails on null bytes). Then decrements `pending` and adds the three counts.

- [ ] **Step 1: Write the failing tests**

```ruby
test "perform renders a range into the live table and skips current rows" do
  feed = @user.feeds.first
  stale, current = create_entry(feed), create_entry(feed)
  EntryRendering.where(entry_id: stale.id).update_all(version: ContentFormatter::VERSION + 1)
  RenderingsRebuild.new.perform("entry_renderings", "range" => [stale.id, current.id])
  assert_equal ContentFormatter::VERSION, EntryRendering.find(stale.id).version
  assert_equal({rendered: 1, skipped: 1, failed: 0}, RenderingsRebuild.progress.except(:pending))
end

test "perform writes an id list into the new table without touching the live one" do
  entry = create_entry(@user.feeds.first)
  ActiveRecord::Base.connection.execute("CREATE TABLE entry_renderings_new (LIKE entry_renderings INCLUDING ALL)")
  before = EntryRendering.find(entry.id).blob
  RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [entry.id, entry.id + 1_000_000])
  assert_equal 1, ActiveRecord::Base.connection.select_value("SELECT count(*) FROM entry_renderings_new").to_i
  assert_equal before, EntryRendering.find(entry.id).blob
ensure
  ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS entry_renderings_new")
end

test "perform rejects an unknown table" do
  assert_raises(ArgumentError) { RenderingsRebuild.new.perform("entries", "ids" => []) }
end

test "a failing entry is counted and the batch continues" do
  a, b = create_entry(@user.feeds.first), create_entry(@user.feeds.first)
  EntryRendering.where(entry_id: [a.id, b.id]).update_all(version: ContentFormatter::VERSION + 1)
  original = EntryRendering.method(:build)
  EntryRendering.stub(:build, ->(entry) { entry.id == a.id ? raise("boom") : original.call(entry) }) do
    RenderingsRebuild.new.perform("entry_renderings", "ids" => [a.id, b.id])
  end
  assert_equal ContentFormatter::VERSION, EntryRendering.find(b.id).version
  assert_equal 1, RenderingsRebuild.progress[:failed]
end

test "start enqueues one job per batch and refuses a second pass" do
  ids = (1..2_500).to_a
  assert_equal 3, RenderingsRebuild.start(ids: ids)
  assert_equal 3, RenderingsRebuild.progress[:pending]
  assert_raises(RuntimeError) { RenderingsRebuild.start(ids: ids) }
  assert_equal 3, RenderingsRebuild.start(ids: ids, force: true)
end
```

`setup` runs `Sidekiq::Worker.clear_all` and `flush_redis`, as `NewsletterBackfillTest` does, and sets `@user = users(:new)` as the other job tests do. Sidekiq runs in fake mode in tests, so `start` fills `RenderingsRebuild.jobs` rather than Redis; the `start` test can also assert `RenderingsRebuild.jobs.size == 3`.

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/jobs/renderings_rebuild_test.rb`
Expected: FAIL, `RenderingsRebuild` uninitialized.

- [ ] **Step 3: Implement** per the Interfaces block.

- [ ] **Step 4: Run the suite**

Run: `rails test`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/renderings_rebuild.rb test/jobs/renderings_rebuild_test.rb
git commit -m "Add RenderingsRebuild"
```

---

### Task 8: Rake tasks: rebuild, status, swap

**Files:**
- Modify: `app/jobs/renderings_rebuild.rb` (`self.swap`, `self.prepare_table`)
- Modify: `lib/tasks/renderings.rake`
- Test: `test/jobs/renderings_rebuild_test.rb`

**Interfaces:**
- Produces `RenderingsRebuild.prepare_table(force: false)`: raises if `entry_renderings_new` exists and not force (drops it when force), then `CREATE TABLE entry_renderings_new (LIKE entry_renderings INCLUDING ALL)` and `ALTER TABLE entry_renderings_new ALTER COLUMN blob SET STORAGE EXTERNAL`.
- Produces `RenderingsRebuild.swap -> Hash` (`{copied:, rows:}`): raises `"Jobs are still running (pending: N)."` when pending > 0; raises when `entry_renderings_new` does not exist. Outside a transaction: `INSERT INTO entry_renderings_new SELECT r.* FROM entry_renderings r WHERE r.version = #{ContentFormatter::VERSION} AND NOT EXISTS (SELECT 1 FROM entry_renderings_new n WHERE n.entry_id = r.entry_id)` (rows the crawler wrote at the current version while the rebuild ran). Then in one transaction: `ALTER TABLE entry_renderings RENAME TO entry_renderings_old; ALTER TABLE entry_renderings_new RENAME TO entry_renderings; ALTER INDEX entry_renderings_new_pkey RENAME TO entry_renderings_pkey`. Then `DROP TABLE entry_renderings_old` and `EntryRendering.reset_column_information`.
- Produces rake tasks in `lib/tasks/renderings.rake`:
  - `renderings:rebuild`: with `FEED=<id>` → `start(ids: Entry.where(feed_id:).pluck(:id))`; with `SINCE=<date>` → `start(ids: Entry.where("created_at >= ?", Date.parse(ENV["SINCE"])).pluck(:id))`; both → the intersection; neither → `prepare_table(force: ENV["FORCE"] == "1")` then `start(table: RenderingsRebuild::NEW_TABLE, force: ENV["FORCE"] == "1")`. Prints the job count and `Watch with rails renderings:status; a full rebuild ends with rails renderings:swap.`
  - `renderings:status`: prints `progress` one counter per line.
  - `renderings:swap`: calls `swap` and prints the copied count and the final row count.

- [ ] **Step 1: Write the failing tests**

```ruby
test "swap refuses while jobs are pending" do
  Sidekiq.redis { _1.set(RenderingsRebuild.key("pending"), 2) }
  assert_raises(RuntimeError) { RenderingsRebuild.swap }
end

test "swap copies rows written during the rebuild and renames the new table into place" do
  feed = @user.feeds.first
  rebuilt, arrived = create_entry(feed), create_entry(feed)
  RenderingsRebuild.prepare_table
  RenderingsRebuild.new.perform("entry_renderings_new", "ids" => [rebuilt.id])
  Sidekiq.redis { _1.set(RenderingsRebuild.key("pending"), 0) }
  result = RenderingsRebuild.swap
  assert_equal 1, result[:copied]
  assert_equal [arrived.id, rebuilt.id].sort, EntryRendering.pluck(:entry_id).sort
  refute ActiveRecord::Base.connection.table_exists?("entry_renderings_new")
  assert_equal "entry_renderings_pkey", ActiveRecord::Base.connection.select_value("SELECT indexname FROM pg_indexes WHERE tablename = 'entry_renderings'")
end

test "prepare_table refuses to clobber an existing new table" do
  RenderingsRebuild.prepare_table
  assert_raises(RuntimeError) { RenderingsRebuild.prepare_table }
  RenderingsRebuild.prepare_table(force: true)
ensure
  ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS entry_renderings_new")
end
```

The swap test renames tables, so it must not run inside the transactional fixture wrapper: mark the test class `self.use_transactional_tests = false` for this file (or move the swap test into its own class) and clean up with `EntryRendering.delete_all` and `Entry.delete_all` in `teardown`.

- [ ] **Step 2: Run to verify failure**

Run: `rails test test/jobs/renderings_rebuild_test.rb`
Expected: FAIL, `swap`/`prepare_table` undefined.

- [ ] **Step 3: Implement** the two class methods and the three rake tasks.

- [ ] **Step 4: Run the suite**

Run: `rails test`
Expected: 0 failures.

- [ ] **Step 5: Exercise the tasks against the development data**

The dev database holds the 67,115 production entries of `rebuild-bench@example.com`. Run (read-only on `entries`; writes only `entry_renderings*`):

```bash
cd ~/Sites/feedbin && source ~/.bash_profile && FEED=$(rails runner 'puts User.find_by!(email: "rebuild-bench@example.com").subscriptions.first.feed_id') rails renderings:rebuild && rails renderings:status
```

Then perform the enqueued jobs inline rather than waiting for a Sidekiq process:

```bash
cd ~/Sites/feedbin && source ~/.bash_profile && rails runner 'Sidekiq::Queue.new("backfill").each { |j| RenderingsRebuild.new.perform(*j.args); j.delete }; p RenderingsRebuild.progress'
```

Expected: `pending: 0`, `failed: 0`, `rendered + skipped` = that feed's entry count.

Then a full pass the same way (about 3 minutes single-process; print progress every 50 jobs so a stall is visible):

```bash
cd ~/Sites/feedbin && source ~/.bash_profile && rails renderings:rebuild && rails runner 'n = 0; Sidekiq::Queue.new("backfill").each { |j| RenderingsRebuild.new.perform(*j.args); j.delete; puts RenderingsRebuild.progress if (n += 1) % 50 == 0 }; p RenderingsRebuild.progress' && rails renderings:swap
```

Expected: swap prints a copied count of 0 or more and a row count equal to `Entry.count`; `rails renderings:status` shows `pending: 0`.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/renderings_rebuild.rb lib/tasks/renderings.rake test/jobs/renderings_rebuild_test.rb
git commit -m "Add renderings:rebuild, status and swap"
```

---

### Task 9: Verify output is unchanged and wrap up

**Files:**
- No code changes expected. Scratch script in `/private/tmp/claude-501/-Users-ben-Sites/b22096ad-3a9c-4a69-b961-13fb6f4b1662/scratchpad/`.

- [ ] **Step 1: Compare stored renderings with live formatting on the 1,000-entry sample**

If `/private/tmp/claude-501/-Users-ben-Sites/b22096ad-3a9c-4a69-b961-13fb6f4b1662/scratchpad/sample_ids.txt` still exists, use it; otherwise take 1,000 random ids from the `rebuild-bench@example.com` feeds. For each entry assert `entry.rendering.web == ContentFormatter.format!(EntryRendering.source_html(entry), entry)`, same for `api`, and `rendering.diff` matches the pre-change `content_diff` rule. Print the count of mismatches.

Expected: 0 mismatches for `web`; for `api` the only difference is `data-camo-src` when camo is configured in `.env` (it is not, so 0).

- [ ] **Step 2: Full suite, then push**

Run: `rails test`
Expected: 0 failures.

```bash
git push -u origin content_formatter
```

- [ ] **Step 3: Record what changed in the design doc**

Add a Decisions row dated the day of completion to `/Users/ben/Sites/feedbin-api-docs/design.md` noting the shipped shape: `rails renderings:rebuild` enqueues, `renderings:status` watches, `renderings:swap` copies rows written during the pass and renames (three commands rather than the one the 2026-10-30 row describes, because a full pass is a day of Sidekiq work the rake process should not have to outlive), and that `diff` is now computed from the same `source_html` as `web` (text-format entries diff their `text_email` output, where before they diffed the raw text). Then `cd ~/Sites/feedbin-api-docs && LANG=en_US.UTF-8 bundle exec rake` must still pass.

---

## Out of scope (follow-ups)

- API v3 (`EntrySerializer#content_html`, `diff`, documenting `data-camo-src` and `proxy_images`) lives on `api-v3-oauth`; wire it to `entry.rendering.api` / `.diff` when the branches meet.
- `EntryMailer` and `StarredEntriesExport` keep calling `api_format` live; both could read `rendering.api` later.
- Dropping the counter caches on `entries` (design.md open question 18) is deferred.
