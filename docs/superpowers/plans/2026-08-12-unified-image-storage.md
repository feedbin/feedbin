# Unified Entry Image Storage on R2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entry preview and link preview images are stored once per original URL as WebP q65 on Cloudflare R2 (dual-written next to the existing S3 jpg path), tracked in an `images` table with consistent metadata, protected by same-feed / site-wide reuse rules, and garbage-collected by refcount when entries are deleted.

**Architecture:** Both image flows already share one Sidekiq pipeline (`Pipeline::Find` → `Download` → `Pipeline::Process` → `Pipeline::Upload` → per-preset callback job). We add a "unified" mode to that pipeline for the `primary`/`twitter`/`youtube` presets: the DB (`images` table) replaces the 1-week Redis positive cache as a permanent dedup index, `Upload` PUTs a second WebP object to R2 and records a row, and the callback payload gains `storage_path`/`bytesize`/`provider` so `entries.image` JSON stays the read model (no N+1 on entry lists). Legacy S3 behavior stays byte-identical during transition (dedup hits still make a per-entry S3 COPY so `EntryDeleter`'s existing deletion keeps working). Deletion adds a refcounting collector guarded by Postgres advisory locks.

**Tech Stack:** Rails 8.1, Sidekiq, Fog::Storage (AWS provider; R2 is S3-compatible), libvips via ImageProcessing::Vips, Postgres, Redis, minitest + webmock.

**Design doc:** `docs/superpowers/specs/2026-08-12-unified-image-storage-design.md`

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`.
- NEVER interpolate values into SQL strings — use hash conditions, binds, or `sanitize_sql_array`. Static SQL fragments in `pluck` must be wrapped in `Arel.sql` with **no** interpolation.
- Do not change behavior for the non-unified presets (`podcast`, `podcast_feed`, `icon`) or the favicon crawler. Existing tests for them must stay green untouched.
- WebP output is exactly quality 65, `strip: true`. Legacy jpg output stays exactly quality 80, `strip: true, background: 255`. Crop dimensions stay 542×304 (`primary`/`twitter`/`youtube`).
- All pipeline jobs remain `retry: false`.
- New env vars (all optional; features are inert without them): `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_REGION` (defaults to `auto`), `R2_BUCKET_IMAGES` (enables dual-write), `R2_IMAGE_HOST` (enables R2 read path), `IMAGE_REUSE_RULES` (enables reuse rules).
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## Deployment notes (not part of this branch's tasks, but why Task 1 is isolated)

`Pipeline::Process`/`Pipeline::Upload` run on host-local queues (`local_queue` appends the hostname) on dedicated crawler machines; deploys are not atomic across hosts and every job is `retry: false`, so an unknown payload attribute raising in `ImageCrawler::Image#initialize` silently drops images mid-deploy. **Task 1 must be deployable on its own, before everything else.** Rollout after merge: deploy Task 1 fleet-wide → deploy the rest → set `R2_*` creds + `R2_BUCKET_IMAGES` (shadow writes begin) → set `IMAGE_REUSE_RULES` → after bake, set `R2_IMAGE_HOST` (read cutover). Stopping the S3 write is a later phase, deliberately not in this plan.

---

### Task 1: Tolerant job-payload initializer

`ImageCrawler::Image#initialize` currently raises `ArgumentError` on unknown attributes. Later tasks add payload attributes; in-flight jobs from newer producers must not crash older consumers (or vice versa) during deploys.

**Files:**
- Modify: `app/jobs/image_crawler/lib/image.rb` (the `initialize` method, lines 88–96)
- Test: `test/jobs/image_crawler/image_test.rb` (new file)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ImageCrawler::Image.new(hash)` ignores unknown keys instead of raising. Known-key behavior unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/jobs/image_crawler/image_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  class ImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    test "ignores unknown attributes" do
      image = Image.new("id" => "abc", "attribute_from_the_future" => "value")
      assert_equal "abc", image.id
    end

    test "sets known attributes" do
      image = Image.new("id" => "abc", "preset_name" => "primary", "image_urls" => ["http://example.com/a.jpg"])
      assert_equal "primary", image.preset_name
      assert_equal ["http://example.com/a.jpg"], image.image_urls
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb`
Expected: FAIL — `ArgumentError: Unknown ImageCrawler::Image attribute: attribute_from_the_future`

- [ ] **Step 3: Make the initializer tolerant**

In `app/jobs/image_crawler/lib/image.rb`, replace the `initialize` method:

```ruby
    # Ignores attributes it does not recognize: pipeline jobs are retry: false
    # and run on host-local queues, so payloads written by a newer deploy must
    # not crash a not-yet-deployed consumer (and vice versa).
    def initialize(data = {})
      data.each do |name, value|
        if ATTRIBUTES.include?(name.to_sym)
          instance_variable_set("@#{name}", value)
        end
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the image crawler suite to check for regressions**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/lib/image.rb test/jobs/image_crawler/image_test.rb
git commit -m "Tolerate unknown image payload attributes

Standalone change, deploy fleet-wide before the rest of the R2 image
work: pipeline payloads gain attributes and jobs are retry: false.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `images` table and `::Image` model API

Recreate the table dropped in `20250117094633_drop_images.rb` with three additions (`feed_id`, `bytesize`, `storage_path` instead of `storage_url`), and give the model the class API every later task calls.

**Files:**
- Create: `db/migrate/<timestamp>_recreate_images.rb` (via generator; class name must NOT be `CreateImages` — that migration class already exists)
- Modify: `app/models/image.rb`
- Modify: `db/structure.sql` (generated by the migration)
- Test: `test/models/image_test.rb` (new file)

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 3, 7, 10, 11):
  - `::Image.url_fingerprint_for(url) → String` — 32-char lowercase MD5 hex of `url.to_s.strip`.
  - `::Image.storage_path_for(url) → String` — `"<fp[0..2]>/<fp>.webp"` where `fp = url_fingerprint_for(url)`.
  - `::Image.attach!(attributes) → ::Image` — upsert keyed by `(provider, provider_id)`; `provider_id` always stored as a string.
  - `::Image.with_url_lock(fingerprint) { ... }` — transaction + `pg_advisory_xact_lock` keyed on the fingerprint; accepts dashed (uuid-from-DB) or undashed (fresh MD5 hex) input and normalizes so both forms take the same lock.
  - Scope `::Image.entry_images` (already exists) — providers `entry_link_preview` + `entry_preview`.
  - Columns: `provider`, `provider_id` (text), `feed_id` (bigint, nullable), `url`, `url_fingerprint` (uuid), `image_fingerprint` (uuid), `storage_path`, `width`, `height`, `bytesize`, `placeholder_color`, `data` (jsonb), timestamps.

- [ ] **Step 1: Generate the migration**

Run: `source ~/.bash_profile && bin/rails generate migration RecreateImages`

- [ ] **Step 2: Fill in the migration**

Edit the generated file to:

```ruby
class RecreateImages < ActiveRecord::Migration[8.1]
  def change
    create_table :images do |t|
      t.bigint :provider,          null: false
      t.text   :provider_id,       null: false
      t.bigint :feed_id
      t.text   :url,               null: false
      t.uuid   :url_fingerprint,   null: false
      t.uuid   :image_fingerprint, null: false
      t.text   :storage_path,      null: false
      t.bigint :width,             null: false
      t.bigint :height,            null: false
      t.bigint :bytesize,          null: false
      t.text   :placeholder_color, null: false
      t.jsonb  :data,              null: false, default: {}

      t.timestamps
    end
    add_index :images, [:provider, :provider_id], unique: true
    add_index :images, :url_fingerprint
    add_index :images, [:feed_id, :image_fingerprint]
  end
end
```

(If the generated migration says a different Rails version in `Migration[x.y]`, keep what the generator produced.)

- [ ] **Step 3: Run the migration**

Run: `source ~/.bash_profile && bin/rails db:migrate && bin/rails db:test:prepare`
Expected: `images` table appears in `db/structure.sql` with the three indexes.

- [ ] **Step 4: Write the failing model tests**

Create `test/models/image_test.rb`:

```ruby
require "test_helper"

class ImageTest < ActiveSupport::TestCase
  test "url_fingerprint_for strips and hashes" do
    assert_equal Digest::MD5.hexdigest("http://example.com/a.jpg"),
      Image.url_fingerprint_for(" http://example.com/a.jpg ")
  end

  test "storage_path_for is sharded by fingerprint prefix" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.webp"),
      Image.storage_path_for("http://example.com/a.jpg")
  end

  test "attach! creates then updates rather than duplicating" do
    attributes = {
      provider: Image.providers[:entry_preview],
      provider_id: 123,
      feed_id: 1,
      url: "http://example.com/a.jpg",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg"),
      width: 542,
      height: 304,
      bytesize: 10_000,
      placeholder_color: "aabbcc"
    }

    record = nil
    assert_difference -> { Image.count }, +1 do
      record = Image.attach!(attributes)
      Image.attach!(attributes.merge(bytesize: 20_000))
    end

    assert_equal "123", record.provider_id
    assert_equal 20_000, record.reload.bytesize
    assert record.url_fingerprint.present?
  end

  test "with_url_lock yields inside a transaction and accepts dashed fingerprints" do
    yielded = false
    Image.with_url_lock("9e107d9d-372b-b682-6bd8-1d3542a419d6") do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end
end
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `source ~/.bash_profile && bin/rails test test/models/image_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'url_fingerprint_for'` (and friends)

- [ ] **Step 6: Implement the model API**

Replace `app/models/image.rb` with:

```ruby
# t.bigint :provider,          null: false
# t.text   :provider_id,       null: false
# t.bigint :feed_id
# t.text   :url,               null: false
# t.uuid   :url_fingerprint,   null: false
# t.uuid   :image_fingerprint, null: false
# t.text   :storage_path,      null: false
# t.bigint :width,             null: false
# t.bigint :height,            null: false
# t.bigint :bytesize,          null: false
# t.text   :placeholder_color, null: false
# t.jsonb  :data,              null: false, default: {}

class Image < ApplicationRecord
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
    website_favicon:    5,     # favicon
    website_touch_icon: 6,     # apple touch icon
  }, prefix: true

  normalizes :url, with: -> url { url.strip }

  scope :feed_icons,   -> { where(provider: %i[feed_icon website_favicon website_touch_icon]) }
  scope :entry_icons,  -> { where(provider: %i[entry_icon website_favicon website_touch_icon]) }
  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  before_save :fingerprint_url

  def self.url_fingerprint_for(url)
    Digest::MD5.hexdigest(url.to_s.strip)
  end

  def self.storage_path_for(url)
    fingerprint = url_fingerprint_for(url)
    File.join(fingerprint[0..2], "#{fingerprint}.webp")
  end

  # Upsert keyed by (provider, provider_id). Not create_or_find_by: a unique
  # violation inside the transactional test wrapper poisons the transaction,
  # and concurrent duplicates are already rare — retry after RecordNotUnique
  # covers the cross-process race.
  def self.attach!(attributes)
    attributes = attributes.symbolize_keys
    attributes[:provider_id] = attributes[:provider_id].to_s
    record = find_by(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id)) ||
      new(provider: attributes.fetch(:provider), provider_id: attributes.fetch(:provider_id))
    record.assign_attributes(attributes)
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Serializes attach vs. garbage collection for one stored object. The
  # fingerprint arrives dashed when read back from the uuid column and
  # undashed when freshly computed; normalize so both take the same lock.
  def self.with_url_lock(fingerprint)
    key = fingerprint.to_s.delete("-")
    transaction do
      connection.select_value(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", key]))
      yield
    end
  end

  private

  def fingerprint_url
    self[:url_fingerprint] = self.class.url_fingerprint_for(url)
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/models/image_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/structure.sql app/models/image.rb test/models/image_test.rb
git commit -m "Recreate images table with usage-per-row schema

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: R2 storage config and unified payload attributes

Add the `STORAGE_R2` Fog config, and teach `ImageCrawler::Image` the unified mode: new attributes, R2 naming/headers, the extended callback payload, and row creation.

**Files:**
- Modify: `config/initializers/s3.rb`
- Modify: `app/jobs/image_crawler/lib/image.rb`
- Modify: `test/test_helper.rb` (boot-time R2 env + `with_env` helper)
- Test: `test/jobs/image_crawler/image_test.rb`

**Interfaces:**
- Consumes: `::Image.url_fingerprint_for`, `::Image.storage_path_for`, `::Image.attach!`, `::Image.with_url_lock` (Task 2).
- Produces (used by Tasks 5–11):
  - `STORAGE_R2` — Fog options hash (AWS provider, `ENV["R2_ENDPOINT"]`, region `ENV["R2_REGION"] || "auto"`, `path_style: true`).
  - New `ImageCrawler::Image` attributes: `feed_id`, `page_url`, `meta_image_urls`, `bytesize`, `webp_path`.
  - `#unified? → bool` — preset opted in (`primary`/`twitter`/`youtube`) AND `ENV["R2_BUCKET_IMAGES"]` present.
  - `#url_fingerprint → String`, `#storage_path → String` (delegate to `::Image` using `original_url`).
  - `#r2_bucket → String` (`ENV["R2_BUCKET_IMAGES"]`), `#r2_storage_options → Hash` (`Content-Type: image/webp`, immutable Cache-Control).
  - `#provider_label → String` (e.g. `"entry_preview"`).
  - `#send_to_feedbin` payload gains `"storage_path"`, `"bytesize"`, `"provider"` keys when `unified?`.
  - `#create_image → ::Image` — attach a row for self under `with_url_lock` (replaces the commented-out version).
  - Test helper `with_env(hash) { ... }` available to all tests.

- [ ] **Step 1: Add `STORAGE_R2` to the initializer**

Append to `config/initializers/s3.rb`:

```ruby
STORAGE_R2 = {}.tap do |hash|
  hash[:provider]              = "AWS"
  hash[:aws_access_key_id]     = ENV["R2_ACCESS_KEY_ID"]
  hash[:aws_secret_access_key] = ENV["R2_SECRET_ACCESS_KEY"]
  hash[:endpoint]              = ENV["R2_ENDPOINT"] if ENV["R2_ENDPOINT"]
  hash[:region]                = ENV["R2_REGION"] || "auto"
  hash[:path_style]            = true
end
```

- [ ] **Step 2: Give tests a boot-time R2 endpoint and a `with_env` helper**

In `test/test_helper.rb`, immediately after the `REDIS_BASE_URL = ...` line and **before** `require File.expand_path("../../config/environment", __FILE__)` (STORAGE_R2 is read at boot):

```ruby
ENV["R2_ENDPOINT"] ||= "https://test-account.r2.cloudflarestorage.com"
ENV["R2_ACCESS_KEY_ID"] ||= "r2-test-key"
ENV["R2_SECRET_ACCESS_KEY"] ||= "r2-test-secret"
```

Then inside `class ActiveSupport::TestCase` (next to `flush_redis` at line ~135), add:

```ruby
  def with_env(vars)
    previous = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
```

Note: `R2_BUCKET_IMAGES` is deliberately NOT set globally — existing tests must keep exercising the legacy path. Unified-path tests opt in with `with_env("R2_BUCKET_IMAGES" => "images-test") { ... }`.

- [ ] **Step 3: Write the failing tests**

Append to `test/jobs/image_crawler/image_test.rb` (inside the class):

```ruby
    test "unified? requires an opted-in preset and the R2 bucket env" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1)
      refute image.unified?

      with_env("R2_BUCKET_IMAGES" => "images-test") do
        assert image.unified?
        podcast = Image.new_with_attributes(id: "a", preset_name: "podcast", image_urls: [], provider: 0, provider_id: 1)
        refute podcast.unified?
      end
    end

    test "storage_path is derived from original_url" do
      image = Image.new_with_attributes(id: "a", preset_name: "primary", image_urls: [], provider: 2, provider_id: 1, original_url: "http://example.com/a.jpg")
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg"), image.storage_path
      assert_equal ::Image.url_fingerprint_for("http://example.com/a.jpg"), image.url_fingerprint
    end

    test "send_to_feedbin includes unified metadata when unified" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 1,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc"
        )
        image.send_to_feedbin

        _, payload = EntryImage.jobs.last["args"]
        assert_equal image.storage_path, payload["storage_path"]
        assert_equal 9_999,              payload["bytesize"]
        assert_equal "entry_preview",    payload["provider"]
      end
    end

    test "send_to_feedbin keeps the legacy payload shape when not unified" do
      image = Image.new_with_attributes(
        id: "a", preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg", final_url: "http://example.com/a.jpg",
        storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
        width: 542, height: 304, placeholder_color: "aabbcc"
      )
      image.send_to_feedbin

      _, payload = EntryImage.jobs.last["args"]
      refute payload.key?("storage_path")
    end

    test "create_image records a usage row" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        image = Image.new_with_attributes(
          id: "a", preset_name: "primary", image_urls: [],
          provider: ::Image.providers[:entry_preview], provider_id: 42, feed_id: 7,
          original_url: "http://example.com/a.jpg", final_url: "http://example.com/a-final.jpg",
          storage_url: "https://s3.amazonaws.com/bucket/a/abc.jpg",
          width: 542, height: 304, bytesize: 9_999, placeholder_color: "aabbcc",
          fingerprint: SecureRandom.hex(16)
        )

        record = image.create_image

        assert_equal "42", record.provider_id
        assert_equal 7, record.feed_id
        assert_equal image.storage_path, record.storage_path
        assert_equal 9_999, record.bytesize
        assert_equal "https://s3.amazonaws.com/bucket/a/abc.jpg", record.data["legacy_storage_url"]
        assert_equal "primary", record.data["preset"]
        assert_equal "http://example.com/a-final.jpg", record.data["final_url"]
      end
    end
```

Also add `setup { flush_redis }` at the top of the class if the sidekiq job assertions interfere between tests (`flush_redis` clears Sidekiq's job queues).

- [ ] **Step 4: Run tests to verify they fail**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'unified?'`

- [ ] **Step 5: Implement the lib changes**

In `app/jobs/image_crawler/lib/image.rb`:

Add to `ATTRIBUTES` (keep the list alphabetized as it is now):

```ruby
      bytesize
      feed_id
      meta_image_urls
      page_url
      webp_path
```

Add `unified: true` to the `primary`, `twitter`, and `youtube` presets in `PRESETS` (e.g. `primary: { width: 542, height: 304, minimum_size: 20_000, crop: :smart_crop, validate: true, unified: true, job_class: EntryImage }`).

Replace `send_to_feedbin` and `create_image`:

```ruby
    def send_to_feedbin
      payload = {
        "original_url"      => final_url,
        "processed_url"     => storage_url,
        "width"             => width,
        "height"            => height,
        "placeholder_color" => placeholder_color
      }
      if unified?
        payload["storage_path"] = storage_path
        payload["bytesize"]     = bytesize
        payload["provider"]     = provider_label
      end
      preset.job_class.perform_async(id, payload)
    end

    def create_image
      ::Image.with_url_lock(url_fingerprint) do
        ::Image.attach!(
          provider: provider,
          provider_id: provider_id,
          feed_id: feed_id,
          url: original_url,
          image_fingerprint: fingerprint,
          storage_path: storage_path,
          width: width,
          height: height,
          bytesize: bytesize,
          placeholder_color: placeholder_color,
          data: {
            "legacy_storage_url" => storage_url,
            "preset"             => preset_name,
            "final_url"          => final_url
          }
        )
      end
    end

    def unified?
      preset.unified == true && ENV["R2_BUCKET_IMAGES"].present?
    end

    def url_fingerprint
      ::Image.url_fingerprint_for(original_url)
    end

    def storage_path
      ::Image.storage_path_for(original_url)
    end

    def provider_label
      ::Image.providers.key(provider)
    end

    def r2_bucket
      ENV["R2_BUCKET_IMAGES"]
    end

    def r2_storage_options
      {
        "Content-Type"  => "image/webp",
        "Cache-Control" => "max-age=315360000, public, immutable"
      }
    end
```

(Keep `image_name`, `bucket`, `storage_options`, `trace` as they are — the legacy path still uses them.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb test/models/image_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add config/initializers/s3.rb app/jobs/image_crawler/lib/image.rb test/test_helper.rb test/jobs/image_crawler/image_test.rb
git commit -m "R2 storage config and unified image payload

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Dual-format output from the cropper

`Processor::Cropper` currently bakes `convert("jpg")` into its geometry pipeline. Split geometry from encoding so one crop can be saved as both jpg q80 (legacy) and WebP q65 (R2) without double-encoding through jpg.

**Files:**
- Modify: `app/jobs/image_crawler/lib/processor/cropper.rb`
- Test: `test/jobs/image_crawler/processor/cropper_test.rb`

**Interfaces:**
- Consumes: `Processed.from_pipeline` / `Processed.from_file` (unchanged).
- Produces (used by Task 5):
  - `Cropper#crop! → Processed` — unchanged public behavior (jpg, or `limit_crop`'s png/jpg/original logic).
  - `Cropper#crop_pair! → {jpg: Processed, webp: Processed}` — same geometry, two encodings. Only valid for `:smart_crop`/`:fill_crop` (the unified presets); `:limit_crop` never dual-writes.

- [ ] **Step 1: Write the failing test**

Append to `test/jobs/image_crawler/processor/cropper_test.rb` (inside the class):

```ruby
      def test_should_crop_pair_in_both_formats
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :fill_crop, extension: "jpeg", width: 542, height: 304)
        pair = cropper.crop_pair!

        assert_equal(542, pair[:jpg].width)
        assert_equal(304, pair[:jpg].height)
        assert pair[:jpg].file.end_with?(".jpg")
        assert_equal(:jpeg, ImageFormat.detect(pair[:jpg].file))

        assert_equal(542, pair[:webp].width)
        assert_equal(304, pair[:webp].height)
        assert pair[:webp].file.end_with?(".webp")
        assert_equal(:webp, ImageFormat.detect(pair[:webp].file))
        assert pair[:webp].size.positive?

        FileUtils.rm pair[:jpg].file
        FileUtils.rm pair[:webp].file
      end

      def test_should_crop_pair_with_smart_crop
        file = copy_support_file("image.jpeg")
        cropper = Processor::Cropper.new(file, crop: :smart_crop, extension: "jpeg", width: 542, height: 304)
        pair = cropper.crop_pair!

        assert_equal(:jpeg, ImageFormat.detect(pair[:jpg].file))
        assert_equal(:webp, ImageFormat.detect(pair[:webp].file))
        assert_equal(pair[:jpg].width, pair[:webp].width)
        assert_equal(pair[:jpg].height, pair[:webp].height)

        FileUtils.rm pair[:jpg].file
        FileUtils.rm pair[:webp].file
      end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/cropper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'crop_pair!'`

- [ ] **Step 3: Refactor the cropper**

In `app/jobs/image_crawler/lib/processor/cropper.rb`:

Add the saver constants near the top of the class (after `PIGO_INSTALLED`):

```ruby
      JPG_SAVER  = {strip: true, quality: 80, background: 255}.freeze
      WEBP_SAVER = {strip: true, quality: 65}.freeze
```

Replace `crop!` and `pipeline`, and add `crop_pair!`, `geometry`, `save_as`:

```ruby
      def crop!
        return limit_crop if @crop == :limit_crop
        Processed.from_pipeline(save_as(geometry, "jpg", JPG_SAVER))
      end

      # One geometry pass, two encodings. Only the fill/smart crops support
      # this; limit_crop (icons) picks its own format and may keep the
      # original file, and never dual-writes.
      def crop_pair!
        cropped = geometry
        {
          jpg:  Processed.from_pipeline(save_as(cropped, "jpg", JPG_SAVER)),
          webp: Processed.from_pipeline(save_as(cropped, "webp", WEBP_SAVER))
        }
      end
```

```ruby
      def geometry
        @geometry ||= send(@crop)
      end

      def save_as(pipeline, format, saver)
        pipeline.convert(format).saver(**saver)
      end

      def pipeline(width, height)
        ImageProcessing::Vips
          .source(source)
          .resize_to_fill(width, height)
      end
```

Change `fill_crop` to return the bare pipeline:

```ruby
      def fill_crop
        pipeline(@width, @height)
      end
```

Change `smart_crop` to return the bare pipeline (its two `Processed.from_pipeline(image)` / `return fill_crop` exits become pipeline returns, and the pigo intermediate encodes explicitly):

```ruby
      def smart_crop
        return fill_crop if resize_too_small? || resize_just_right?

        image = pipeline(proposed_size.width, proposed_size.height)

        if proposed_size.width > @width
          axis = "x"
          contraint = @width
          max = proposed_size.width - @width
        else
          axis = "y"
          contraint = @height
          max = proposed_size.height - @height
        end

        if PIGO_INSTALLED && center = average_face_position(axis, save_as(image, "jpg", JPG_SAVER).call)
          point = {"x" => 0, "y" => 0}
          point[axis] = (center.to_f - contraint.to_f / 2.0).floor

          if point[axis] < 0
            point[axis] = 0
          elsif point[axis] > max
            point[axis] = max
          end

          image = image.crop(point["x"], point["y"], @width, @height)
        else
          image = image.resize_to_fill(@width, @height, crop: :attention)
        end

        image
      end
```

`limit_crop` stays exactly as it is (it already returns a `Processed`).

- [ ] **Step 4: Run the cropper tests (old and new) to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/cropper_test.rb`
Expected: PASS — including the pre-existing `crop!` tests (jpg output, limit_crop png/jpg/original behavior, 640×828 same-size case).

- [ ] **Step 5: Run the wider pipeline tests for regressions**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/lib/processor/cropper.rb test/jobs/image_crawler/processor/cropper_test.rb
git commit -m "Split crop geometry from encoding, add webp output

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Dual output in `Pipeline::Process`

For unified images, produce both encodings, and take `bytesize` + `image_fingerprint` from the WebP (the canonical new-system object).

**Files:**
- Modify: `app/jobs/image_crawler/pipeline/process.rb`
- Test: `test/jobs/image_crawler/pipeline/process_test.rb`

**Interfaces:**
- Consumes: `Cropper#crop_pair!` (Task 4), `ImageCrawler::Image#unified?` (Task 3).
- Produces (used by Task 6): `Upload` payloads where, when unified, `webp_path` points at the WebP temp file, `bytesize` is the WebP byte count, and `fingerprint` is the WebP MD5. Legacy payload fields (`processed_path`, `width`, `height`, `placeholder_color`, `processed_extension`) unchanged and still describing the jpg.
- Produces: private `Process#requeue_remaining` — re-enqueues `FindCritical` with the remaining candidate urls, carrying `feed_id`/`page_url`/`meta_image_urls` through (Task 10 reuses it for reuse-rule rejections).

- [ ] **Step 1: Read the existing process test**

Run: `source ~/.bash_profile && cat test/jobs/image_crawler/pipeline/process_test.rb`
Follow its conventions for the new tests (it builds an `Image` payload around `copy_support_file("image.jpeg")` and asserts on `Upload.jobs`).

- [ ] **Step 2: Write the failing test**

Append to the test class in `test/jobs/image_crawler/pipeline/process_test.rb`:

```ruby
      def test_should_produce_webp_for_unified_presets
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          download_path = copy_support_file("image.jpeg")
          image = Image.new_with_attributes(
            id: SecureRandom.hex,
            preset_name: "primary",
            image_urls: [],
            provider: ::Image.providers[:entry_preview],
            provider_id: 1,
            feed_id: 1,
            original_url: "http://example.com/image.jpg",
            final_url: "http://example.com/image.jpg",
            download_path: download_path,
            original_extension: "jpeg"
          )

          assert_difference -> { Upload.jobs.size }, +1 do
            Process.new.perform(image.to_h)
          end

          queued = Image.new(Upload.jobs.last["args"].first)
          assert queued.webp_path.present?
          assert_equal :webp, ImageFormat.detect(queued.webp_path)
          assert_equal File.size(queued.webp_path), queued.bytesize
          assert_equal Digest::MD5.file(queued.webp_path).hexdigest, queued.fingerprint
          assert_equal "jpg", queued.processed_extension
          assert_equal 542, queued.width
          assert_equal 304, queued.height

          File.unlink(queued.processed_path)
          File.unlink(queued.webp_path)
        end
      end

      def test_should_not_produce_webp_without_r2_configuration
        download_path = copy_support_file("image.jpeg")
        image = Image.new_with_attributes(
          id: SecureRandom.hex,
          preset_name: "primary",
          image_urls: [],
          provider: ::Image.providers[:entry_preview],
          provider_id: 1,
          original_url: "http://example.com/image.jpg",
          download_path: download_path,
          original_extension: "jpeg"
        )

        Process.new.perform(image.to_h)

        queued = Image.new(Upload.jobs.last["args"].first)
        assert_nil queued.webp_path
        File.unlink(queued.processed_path)
      end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/process_test.rb`
Expected: FAIL — `webp_path` is nil in the unified test.

- [ ] **Step 4: Implement**

Replace `Process#perform` in `app/jobs/image_crawler/pipeline/process.rb`:

```ruby
      def perform(image_hash)
        @image = Image.new(image_hash)
        Sidekiq.logger.info "Process: public_id=#{@image.id} final_url=#{@image.final_url}"

        processor = Processor::Cropper.new(@image.download_path,
          crop:      @image.preset.crop,
          extension: @image.original_extension,
          width:     @image.preset.width,
          height:    @image.preset.height
        )

        if processor.valid?(@image.validate?)
          if @image.unified?
            pair = processor.crop_pair!
            cropped = pair[:jpg]
            webp = pair[:webp]

            @image.webp_path   = webp.file
            @image.bytesize    = webp.size
            @image.fingerprint = webp.fingerprint
          else
            cropped = processor.crop!
            @image.fingerprint = cropped.fingerprint
          end

          @image.processed_path      = cropped.file
          @image.width               = cropped.width
          @image.height              = cropped.height
          @image.placeholder_color   = cropped.placeholder_color
          @image.processed_extension = cropped.extension

          Upload.perform_async(@image.to_h)
        else
          requeue_remaining
        end
      ensure
        File.unlink(@image.download_path) rescue Errno::ENOENT
      end

      def requeue_remaining
        return if @image.image_urls.empty?
        image = Image.new_with_attributes(
          id: @image.id,
          preset_name: @image.preset_name,
          image_urls: @image.image_urls,
          provider: @image.provider,
          provider_id: @image.provider_id,
          feed_id: @image.feed_id,
          page_url: @image.page_url,
          meta_image_urls: @image.meta_image_urls
        )
        FindCritical.perform_async(image.to_h)
      end
```

(The old `else` branch built the retry image inline and guarded with `unless @image.image_urls.empty?` — same behavior, now in `requeue_remaining`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/process_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/pipeline/process.rb test/jobs/image_crawler/pipeline/process_test.rb
git commit -m "Process produces webp alongside jpg for unified presets

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Dual-write in `Pipeline::Upload`

PUT the WebP to R2 with correct headers, record the `::Image` row, and stop writing the Redis positive cache for unified images (the row replaces it).

**Files:**
- Modify: `app/jobs/image_crawler/pipeline/upload.rb`
- Test: `test/jobs/image_crawler/pipeline/upload_test.rb`

**Interfaces:**
- Consumes: `ImageCrawler::Image#unified?`, `#r2_bucket`, `#storage_path`, `#r2_storage_options`, `#create_image`, `#webp_path` (Tasks 3, 5); `STORAGE_R2` (Task 3).
- Produces: R2 object at `storage_path`; one `::Image` row per uploaded image; callback payload via the already-extended `send_to_feedbin`. Legacy path (`DownloadCache.save`, single S3 PUT) untouched for non-unified presets.

- [ ] **Step 1: Write the failing test**

Append to the test class in `test/jobs/image_crawler/pipeline/upload_test.rb`:

```ruby
      def test_should_dual_write_unified_images
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          id = SecureRandom.hex
          download_path = copy_support_file("image.jpeg")
          webp_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/image.jpg"

          image = Image.new_with_attributes(
            id: id, preset_name: "primary", image_urls: [],
            provider: ::Image.providers[:entry_preview], provider_id: 1, feed_id: 1,
            fingerprint: SecureRandom.hex(16),
            original_url: original_url, final_url: original_url,
            download_path: download_path, processed_path: download_path,
            webp_path: webp_path, bytesize: File.size(webp_path),
            width: 542, height: 304, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          r2_put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .with(headers: {"Content-Type" => "image/webp"})

          assert_difference -> { ::Image.count }, +1 do
            assert_difference -> { EntryImage.jobs.size }, +1 do
              Upload.new.perform(image.to_h)
            end
          end

          assert_requested r2_put

          record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(original_url))
          assert_equal "1", record.provider_id
          assert_equal image.storage_path, record.storage_path
          assert record.data["legacy_storage_url"].present?

          _, payload = EntryImage.jobs.last["args"]
          assert_equal image.storage_path, payload["storage_path"]

          # the positive redis cache is retired for unified images
          assert_nil DownloadCache.new(original_url, image).cached_image
        end
      end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/upload_test.rb`
Expected: FAIL — no request to `r2.cloudflarestorage.com`, `::Image.count` unchanged.

- [ ] **Step 3: Implement**

Replace `app/jobs/image_crawler/pipeline/upload.rb` contents of `perform` and add `upload_r2`:

```ruby
      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload

        if @image.unified?
          upload_r2
          @image.create_image
          Librato.increment("image.r2_upload")
        else
          DownloadCache.save(@image)
        end

        @image.send_to_feedbin
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_url=#{@image.storage_url} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path)
        begin
          File.unlink(@image.webp_path) if @image.webp_path
        rescue Errno::ENOENT
        end
      end

      def upload_r2
        File.open(@image.webp_path) do |file|
          Fog::Storage.new(STORAGE_R2).put_object(@image.r2_bucket, @image.storage_path, file, @image.r2_storage_options)
        end
      end
```

(The existing `upload` method stays exactly as it is.)

Note the ordering: the R2 object exists before the row that references it, and the row exists before the callback runs. If `upload_r2` or `create_image` raises, the job dies (retry: false) without a dangling row; an orphaned R2 object is acceptable dust.

- [ ] **Step 4: Run tests to verify they pass (including the legacy upload test)**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/upload_test.rb`
Expected: PASS — `test_should_upload` (legacy) and the new dual-write test.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/image_crawler/pipeline/upload.rb test/jobs/image_crawler/pipeline/upload_test.rb
git commit -m "Dual-write unified images to R2 and record image rows

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: DB-backed dedup in `Pipeline::Find`

Replace the Redis positive cache with an `images`-table lookup for unified presets. On a hit: no download, no reprocess — copy only the legacy S3 object (per-entry, so `EntryDeleter` keeps working), attach a row for this entry under the advisory lock, and fire the callback.

**Files:**
- Create: `app/jobs/image_crawler/lib/dedupe.rb`
- Modify: `app/jobs/image_crawler/pipeline/find.rb`
- Test: `test/jobs/image_crawler/dedupe_test.rb` (new file)
- Test: `test/jobs/image_crawler/pipeline/find_test.rb`

**Interfaces:**
- Consumes: `::Image.entry_images`, `::Image.url_fingerprint_for`, `::Image.attach!`, `::Image.with_url_lock` (Task 2); `ImageCrawler::Image#unified?`, `#send_to_feedbin`, `#image_name`, `#bucket`, `#storage_options` (Task 3); `DownloadCache#download?` / `#failed!` (unchanged, still the negative-attempt cache).
- Produces (used by Task 10's Find changes and Task 11's GC race reasoning):
  - `Dedupe.attach(original_url, image) → bool` — true when the entry was attached to an already-stored image (callback fired); false when the caller should download normally (no row, legacy copy source gone, or GC deleted the object mid-flight).

- [ ] **Step 1: Write the failing Dedupe unit tests**

Create `test/jobs/image_crawler/dedupe_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  class DedupeTest < ActiveSupport::TestCase
    setup do
      flush_redis
      @original_url = "http://example.com/image.jpg"
      @image = Image.new_with_attributes(
        id: SecureRandom.hex,
        preset_name: "primary",
        image_urls: [],
        provider: ::Image.providers[:entry_preview],
        provider_id: 2,
        feed_id: 9
      )
    end

    def seed_row(provider_id: 1, data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", "final_url" => "http://example.com/image-final.jpg"})
      ::Image.create!(
        provider: :entry_preview,
        provider_id: provider_id.to_s,
        feed_id: 9,
        url: @original_url,
        image_fingerprint: SecureRandom.hex(16),
        storage_path: ::Image.storage_path_for(@original_url),
        width: 542, height: 304, bytesize: 12_345,
        placeholder_color: "aabbcc",
        data: data
      )
    end

    test "returns false when nothing is stored for the url" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        refute Dedupe.attach(@original_url, @image)
      end
    end

    test "attaches to an existing image without downloading" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        row = seed_row
        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

        assert_difference -> { ::Image.count }, +1 do
          assert Dedupe.attach(@original_url, @image)
        end

        attached = ::Image.entry_images.find_by(provider_id: "2")
        assert_equal row.storage_path, attached.storage_path
        assert_equal row.image_fingerprint, attached.image_fingerprint
        assert_equal 12_345, attached.bytesize
        assert attached.data["legacy_storage_url"].include?(@image.image_name)

        _, payload = EntryImage.jobs.last["args"]
        assert_equal row.storage_path, payload["storage_path"]
        assert_equal 12_345, payload["bytesize"]
        assert_equal "http://example.com/image-final.jpg", payload["original_url"]
      end
    end

    test "falls back to download when the legacy copy source is gone" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        seed_row
        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 404)

        assert_no_difference -> { ::Image.count } do
          refute Dedupe.attach(@original_url, @image)
        end
        assert_equal 0, EntryImage.jobs.size
      end
    end

    test "falls back to download when GC removed the rows mid-flight" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        seed_row
        stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

        dedupe = Dedupe.new(@original_url, @image)
        ::Image.delete_all

        refute dedupe.attach
        assert_equal 0, EntryImage.jobs.size
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/dedupe_test.rb`
Expected: FAIL — `NameError: uninitialized constant ImageCrawler::Dedupe`

- [ ] **Step 3: Implement `Dedupe`**

Create `app/jobs/image_crawler/lib/dedupe.rb`:

```ruby
module ImageCrawler
  # Attaches an entry to an already-stored unified image so the same
  # original_url is never downloaded or processed twice. The legacy S3 object
  # is still copied per entry (EntryDeleter deletes per-entry legacy objects);
  # the R2 object is shared and refcounted by images rows.
  class Dedupe
    attr_reader :record

    def self.attach(original_url, image)
      new(original_url, image).attach
    end

    def initialize(original_url, image)
      @original_url = original_url.to_s
      @image = image
      @record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(@original_url))
    end

    # Returns true when the entry was attached to an existing image and the
    # callback was enqueued. False means: download the candidate normally.
    def attach
      return false if record.nil?

      legacy_url = copy_legacy_object
      return false if legacy_url.nil?

      attached = nil
      ::Image.with_url_lock(record.url_fingerprint) do
        # If GC removed the last reference (and the R2 object) between our
        # lookup and here, we must not reference a deleted object.
        if ::Image.entry_images.where(url_fingerprint: record.url_fingerprint).exists?
          attached = ::Image.attach!(
            provider: @image.provider,
            provider_id: @image.provider_id,
            feed_id: @image.feed_id,
            url: @original_url,
            image_fingerprint: record.image_fingerprint,
            storage_path: record.storage_path,
            width: record.width,
            height: record.height,
            bytesize: record.bytesize,
            placeholder_color: record.placeholder_color,
            data: {
              "legacy_storage_url" => legacy_url,
              "preset"             => @image.preset_name,
              "final_url"          => final_url
            }
          )
        end
      end
      return false if attached.nil?

      @image.original_url      = @original_url
      @image.final_url         = final_url
      @image.storage_url       = legacy_url
      @image.width             = record.width
      @image.height            = record.height
      @image.bytesize          = record.bytesize
      @image.placeholder_color = record.placeholder_color
      @image.fingerprint       = record.image_fingerprint
      @image.send_to_feedbin
      true
    end

    private

    def final_url
      record.data["final_url"].presence || @original_url
    end

    # Same mechanics as the legacy DownloadCache#copy_image: give this entry
    # its own copy of the processed S3 object so per-entry legacy deletion
    # stays valid during the transition.
    def copy_legacy_object
      source_url = record.data["legacy_storage_url"]
      return nil if source_url.blank?

      url = URI.parse(source_url)
      source_object_name = url.path[1..-1]
      @image.processed_extension = File.extname(source_object_name).delete(".")
      destination = @image.image_name
      Fog::Storage.new(STORAGE).copy_object(@image.bucket, source_object_name, @image.bucket, destination, @image.storage_options)
      url.path = "/#{destination}"
      url.to_s
    rescue Excon::Error::NotFound
      nil
    end
  end
end
```

Note on `image_name`: with `processed_extension` set first, `image_name` returns `"abc/abcdef123.jpg"` — unlike the legacy `DownloadCache#copy_image`, which appends the extension after a trailing dot. Both produce valid keys; this one is cleaner and only used for new copies.

- [ ] **Step 4: Run the Dedupe tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/dedupe_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 5: Write the failing Find integration test**

Append to the test class in `test/jobs/image_crawler/pipeline/find_test.rb`:

```ruby
      def test_should_attach_existing_unified_image_without_downloading
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/image.jpg"
          ::Image.create!(
            provider: :entry_preview,
            provider_id: "1",
            feed_id: 9,
            url: original_url,
            image_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.storage_path_for(original_url),
            width: 542, height: 304, bytesize: 12_345,
            placeholder_color: "aabbcc",
            data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg"}
          )
          stub_request(:put, /s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

          image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)
          Find.new.perform(image.to_h)

          assert_equal 1, EntryImage.jobs.size
          refute_requested :get, original_url
          assert_equal 2, ::Image.entry_images.where(url_fingerprint: ::Image.url_fingerprint_for(original_url)).count
        end
      end

      def test_should_download_unified_image_on_dedupe_miss
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/image.jpg"
          stub_request_file("image.jpeg", original_url, headers: {content_type: "image/jpeg"})

          image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)

          assert_difference -> { Process.jobs.size }, +1 do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
        end
      end
```

- [ ] **Step 6: Run to verify the first new Find test fails**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/find_test.rb`
Expected: the attach test FAILS (Find still uses `DownloadCache.copy`, which finds nothing in Redis and downloads — `refute_requested :get` trips or `EntryImage.jobs` is empty). The miss test may already pass.

- [ ] **Step 7: Rework the Find candidate loop**

In `app/jobs/image_crawler/pipeline/find.rb`, replace the `while` loop body's cache/download branch (keep the count/timer guards exactly as they are) and extract the legacy branch:

```ruby
        while original_url = @image.image_urls.shift
          count += 1

          if count > 10
            Sidekiq.logger.info @image.trace(message: "exceeded count limit", metadata: {count: count})
            break
          end

          if timer.expired?
            Sidekiq.logger.info @image.trace(message: "exceeded total time limit", metadata: {elapsed_time: timer.elapsed})
            break
          end

          Sidekiq.logger.info @image.trace(message: "attempting image candidate", metadata: {original_url: original_url})

          if @image.unified?
            break if attempt_unified(original_url)
          else
            break if attempt_legacy(original_url)
          end
        end
```

Add the two private methods (the legacy one is the old loop body, verbatim, returning true where it used to `break`):

```ruby
      def attempt_unified(original_url)
        download_cache = DownloadCache.new(original_url, @image)

        if Dedupe.attach(original_url, @image)
          Librato.increment("image.dedupe_hit")
          Sidekiq.logger.info @image.trace(message: "attached existing image", metadata: {original_url: original_url})
          true
        elsif download_cache.download?
          download_image(original_url, download_cache)
        else
          Sidekiq.logger.info @image.trace(message: "skipping image", metadata: {original_url: original_url})
          false
        end
      end

      def attempt_legacy(original_url)
        download_cache = DownloadCache.copy(original_url, @image)

        if download_cache.copied?
          image             = download_cache.cached_image
          image.storage_url = download_cache.storage_url
          image.id          = @image.id
          image.provider    = @image.provider
          image.provider_id = @image.provider_id

          image.send_to_feedbin

          Sidekiq.logger.info @image.trace(message: "copied existing image", metadata: {image_url: @image.final_url, storage_url: @image.storage_url})
          true
        elsif download_cache.download?
          download_image(original_url, download_cache)
        else
          Sidekiq.logger.info @image.trace(message: "skipping image", metadata: {image_url: @image.final_url})
          false
        end
      end
```

(`DownloadCache.new` — not `.copy` — in the unified branch: it still provides `download?`, the negative "already tried and failed" check, and `download_image` calls its `failed!` on invalid downloads. The positive Redis cache is simply never consulted or written for unified images.)

- [ ] **Step 8: Run the Find tests to verify everything passes**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/find_test.rb test/jobs/image_crawler/dedupe_test.rb`
Expected: PASS — new tests plus all pre-existing legacy Find tests (copy, meta fetch, recognized urls, camo, try-all-urls).

- [ ] **Step 9: Commit**

```bash
git add app/jobs/image_crawler/lib/dedupe.rb app/jobs/image_crawler/pipeline/find.rb test/jobs/image_crawler/dedupe_test.rb test/jobs/image_crawler/pipeline/find_test.rb
git commit -m "DB-backed image dedup for unified presets

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Producers and callbacks carry the new metadata

`EntryImage` and `TwitterLinkImage` pass `feed_id`/`page_url`/`meta_image_urls` into the pipeline; `Find#combine_urls` marks page-fetched meta urls; `TwitterLinkImage#receive` stores the full metadata hash on the entry.

**Files:**
- Modify: `app/jobs/image_crawler/entry_image.rb`
- Modify: `app/jobs/image_crawler/twitter_link_image.rb`
- Modify: `app/jobs/image_crawler/pipeline/find.rb` (`combine_urls`)
- Test: `test/jobs/image_crawler/entry_image_test.rb`
- Test: `test/jobs/image_crawler/twitter_link_image_test.rb`

**Interfaces:**
- Consumes: `ImageCrawler::Image` attributes from Task 3.
- Produces (used by Task 10):
  - Every `Pipeline::Find` payload for entry images carries `feed_id` (integer), `page_url` (the entry's fully-qualified URL / the linked page), and `meta_image_urls` (string array — the subset of `image_urls` that came from `og:image`/`twitter:image` meta tags).
  - `Find#combine_urls` appends `MetaImages.find_urls` results (stringified) to `@image.meta_image_urls`.
  - `entries.data["link_image"]` — full metadata hash for link previews: `original_url`, `processed_url`, `width`, `height`, `placeholder_color`, and when unified `storage_path`, `bytesize`, `provider`. Old keys (`twitter_link_image_processed`, `twitter_link_image_placeholder_color`) still written.

- [ ] **Step 1: Write the failing producer tests**

Append to `test/jobs/image_crawler/entry_image_test.rb` (inside the class; note this file uses `test "..."` blocks):

```ruby
    test "should enqueue Find with feed context and meta urls" do
      content = <<-EOT
      <meta property="og:image" content="/og">
      <img src="/img">
      EOT

      entry = @feed.entries.create(
        content: content,
        public_id: SecureRandom.hex,
        url: "http://example.com/article"
      )

      EntryImage.new.perform(entry.public_id)

      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      assert_equal @feed.id, image.feed_id
      assert_equal entry.fully_qualified_url, image.page_url
      assert_equal ["http://example.com/og"], image.meta_image_urls
      assert_equal ["http://example.com/og", "http://example.com/img"], image.image_urls
    end
```

Append to the test class in `test/jobs/image_crawler/twitter_link_image_test.rb` (read the file first and follow its entry-creation setup):

```ruby
    test "should enqueue Find with feed context" do
      entry = Feed.first.entries.create(
        content: "content",
        public_id: SecureRandom.hex,
        url: "http://example.com/article"
      )

      TwitterLinkImage.new.perform(entry.public_id, nil, "http://example.com/linked-page")

      image = Image.new(Pipeline::Find.jobs.first["args"].first)
      assert_equal entry.feed_id, image.feed_id
      assert_equal "http://example.com/linked-page", image.page_url
      assert_equal "http://example.com/linked-page", image.entry_url
    end

    test "should store the full link_image metadata" do
      entry = Feed.first.entries.create(
        content: "content",
        public_id: SecureRandom.hex,
        url: "http://example.com/article",
        data: {}
      )

      payload = {
        "original_url" => "http://example.com/image.jpg",
        "processed_url" => "https://bucket.s3.amazonaws.com/abc/abc.jpg",
        "width" => 542,
        "height" => 304,
        "bytesize" => 12_345,
        "placeholder_color" => "aabbcc",
        "storage_path" => "abc/abcdef.webp",
        "provider" => "entry_link_preview"
      }
      TwitterLinkImage.new.perform("#{entry.public_id}-twitter", payload)

      entry.reload
      assert_equal payload, entry.data["link_image"]
      assert_equal payload["processed_url"], entry.data["twitter_link_image_processed"]
      assert_equal "aabbcc", entry.data["twitter_link_image_placeholder_color"]
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/entry_image_test.rb test/jobs/image_crawler/twitter_link_image_test.rb`
Expected: FAIL — `feed_id`/`page_url`/`meta_image_urls` nil, `data["link_image"]` nil.

- [ ] **Step 3: Implement `EntryImage` changes**

In `app/jobs/image_crawler/entry_image.rb`:

`find_image_urls` returns `[url, meta?]` pairs:

```ruby
    def find_image_urls
      Nokogiri::HTML5(@entry.content)
        .css(IMAGE_SELECTORS.join(","))
        .sort_by do |element|
          IMAGE_SELECTORS.index { element.matches?(_1) }
        end
        .each_with_object([]) do |element, array|
          source =      case element.name
          when "img"    then element["src"]
          when "iframe" then element["src"]
          when "video"  then element["poster"]
          when "meta"   then element["content"]
          end

          array.push([@entry.rebase_url(source), element.name == "meta"]) if source.present?
        end
    end
```

`build_job` unpacks the pairs and passes the new attributes:

```ruby
    def build_job
      image_urls = []
      meta_image_urls = []
      entry_url = nil
      preset_name = "primary"
      if @entry.tweet?
        tweets = []
        tweets.push(@entry.tweet.main_tweet)
        tweets.push(@entry.tweet.main_tweet.quoted_status) if @entry.tweet.main_tweet.quoted_status?
        tweet = tweets.find do |tweet|
          tweet.media?
        end
        image_urls = [tweet.media.first.media_url_https.to_s] unless tweet.nil?
      elsif @entry.youtube?
        image_urls = [@entry.fully_qualified_url]
        preset_name = "youtube"
      elsif @entry.micropost?
        found = find_image_urls
        image_urls = found.map(&:first)
        meta_image_urls = found.select(&:last).map(&:first)
        @entry.media.each do |media|
          image_urls.push(media.url) if media.type =~ /image/i
        end
      else
        entry_url = @entry.fully_qualified_url if same_domain?
        found = find_image_urls
        image_urls = found.map(&:first)
        meta_image_urls = found.select(&:last).map(&:first)
      end

      if image_urls.present? || entry_url.present?
        Image.new_with_attributes(
          id:              @entry.public_id,
          preset_name:     preset_name,
          image_urls:      image_urls,
          provider:        ::Image.providers[:entry_preview],
          provider_id:     @entry.id,
          entry_url:       entry_url,
          feed_id:         @entry.feed_id,
          page_url:        @entry.fully_qualified_url,
          meta_image_urls: meta_image_urls
        ).to_h
      end
    end
```

- [ ] **Step 4: Implement `TwitterLinkImage` changes**

In `app/jobs/image_crawler/twitter_link_image.rb`:

```ruby
    def schedule
      image = Image.new_with_attributes(
        id: "#{@entry.public_id}-twitter",
        preset_name: "twitter",
        image_urls: [],
        provider: ::Image.providers[:entry_link_preview],
        provider_id: @entry.id,
        entry_url: @page_url,
        feed_id: @entry.feed_id,
        page_url: @page_url
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    def receive
      @entry.data["twitter_link_image_processed"] = @image["processed_url"]
      @entry.data["twitter_link_image_placeholder_color"] = @image["placeholder_color"]
      @entry.data["link_image"] = @image
      @entry.save!
    end
```

- [ ] **Step 5: Mark page-fetched meta urls in `Find#combine_urls`**

In `app/jobs/image_crawler/pipeline/find.rb`, replace `combine_urls`:

```ruby
      def combine_urls(image_urls, entry_url)
        return image_urls unless entry_url

        page_urls = if Download.find_download_provider(entry_url)
          Sidekiq.logger.info "Recognized URL: entry_url=#{entry_url}"
          [entry_url]
        else
          found = MetaImages.find_urls(entry_url).map(&:to_s)
          Sidekiq.logger.info "MetaImages: count=#{found.length} entry_url=#{entry_url}"
          @image.meta_image_urls = (@image.meta_image_urls || []) | found
          found
        end

        page_urls ||= []
        page_urls.concat(image_urls || [])
      end
```

(This also fixes the pre-existing bug where the log line referenced `page_urls` before assignment and always printed `count=0`.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler`
Expected: PASS — new tests plus all pre-existing ones (the parsed-urls ordering test keeps passing because `image_urls` is still the flat ordered list).

- [ ] **Step 7: Commit**

```bash
git add app/jobs/image_crawler/entry_image.rb app/jobs/image_crawler/twitter_link_image.rb app/jobs/image_crawler/pipeline/find.rb test/jobs/image_crawler/entry_image_test.rb test/jobs/image_crawler/twitter_link_image_test.rb
git commit -m "Carry feed context and meta-url provenance through the image pipeline

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: R2 read path on `Entry`

New reads prefer `storage_path` + `R2_IMAGE_HOST`; everything else falls back to today's behavior (including the `ENTRY_IMAGE_HOST` rewrite, which must apply to legacy URLs only).

**Files:**
- Modify: `app/models/entry.rb` (`processed_image`, `link_image`, `link_image_placeholder_color`)
- Test: `test/models/entry_test.rb`

**Interfaces:**
- Consumes: `entries.image["storage_path"]` and `entries.data["link_image"]` written by Tasks 3–8.
- Produces: `Entry#processed_image`, `Entry#link_image`, `Entry#link_image_placeholder_color` — same signatures, R2-aware. All existing consumers (`EntryPresenter#image`, `entry_image_component.rb`, `_entry.html.erb`, API v2 `_entry_extended.json.jbuilder`) keep working unchanged.

- [ ] **Step 1: Write the failing tests**

Append to the test class in `test/models/entry_test.rb` (read the file first; follow its entry-creation conventions):

```ruby
  test "processed_image prefers R2 when configured" do
    entry = create_entry(Feed.first)
    entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "storage_path" => "abc/abcdef123.webp",
      "width" => 542,
      "height" => 304,
      "placeholder_color" => "aabbcc"
    })

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/abc/abcdef123.webp", entry.processed_image
      assert entry.processed_image?
    end

    with_env("R2_IMAGE_HOST" => nil) do
      assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", entry.processed_image
    end
  end

  test "processed_image ignores R2 host for legacy images without a storage_path" do
    entry = create_entry(Feed.first)
    entry.update(image: {
      "original_url" => "http://example.com/image.jpg",
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg",
      "width" => 542,
      "height" => 304
    })

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef.jpg", entry.processed_image
    end
  end

  test "link_image prefers R2 and falls back to legacy keys" do
    entry = create_entry(Feed.first)
    entry.data ||= {}
    entry.data["link_image"] = {
      "processed_url" => "https://bucket.s3.amazonaws.com/abc/abcdef-twitter.jpg",
      "storage_path" => "abc/abcdef123.webp",
      "placeholder_color" => "bbccdd"
    }
    entry.data["twitter_link_image_processed"] = "https://bucket.s3.amazonaws.com/abc/abcdef-twitter.jpg"
    entry.data["twitter_link_image_placeholder_color"] = "ccddee"
    entry.save!

    with_env("R2_IMAGE_HOST" => "https://images.example.com") do
      assert_equal "https://images.example.com/abc/abcdef123.webp", entry.link_image
      assert_equal "bbccdd", entry.link_image_placeholder_color
    end

    with_env("R2_IMAGE_HOST" => nil) do
      assert_equal "https://bucket.s3.amazonaws.com/abc/abcdef-twitter.jpg", entry.link_image
    end
  end
```

(`with_env(... => nil)` works because the helper deletes keys restored to nil — check the Task 3 helper: it sets `ENV[key] = value`; setting a key to nil via `ENV[key] = nil` deletes it in Ruby. Both directions behave.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `source ~/.bash_profile && bin/rails test test/models/entry_test.rb`
Expected: FAIL — R2 assertions return the S3 URL.

- [ ] **Step 3: Implement the read path**

In `app/models/entry.rb`, replace `processed_image`, `link_image`, and `link_image_placeholder_color`:

```ruby
  def processed_image
    return unless image

    if r2_url = r2_image_url(image["storage_path"])
      return r2_url
    end

    if image["original_url"] && image["width"] && image["height"] && image["processed_url"]
      image_url = image["processed_url"]
      host = ENV["ENTRY_IMAGE_HOST"]
      url = URI(image_url)
      unless Rails.env.development?
        url.scheme = "https"
      end
      url.host = host if host
      url.to_s
    end
  end
```

```ruby
  def link_image
    link_image_data = data && data["link_image"]

    if link_image_data && (r2_url = r2_image_url(link_image_data["storage_path"]))
      return r2_url
    end

    if data && data["twitter_link_image_processed"]
      image_url = data["twitter_link_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def link_image_placeholder_color
    color = data && (data.dig("link_image", "placeholder_color") || data["twitter_link_image_placeholder_color"])
    if color.respond_to?(:length) && color.length == 6
      color
    end
  end
```

And add the private helper (put it near the other private methods at the bottom of the class):

```ruby
  def r2_image_url(storage_path)
    return nil if storage_path.blank?
    return nil if ENV["R2_IMAGE_HOST"].blank?
    [ENV["R2_IMAGE_HOST"].chomp("/"), storage_path].join("/")
  end
```

Note: the `ENTRY_IMAGE_HOST` rewrite is only ever applied to legacy `processed_url` values — R2 URLs are built from `R2_IMAGE_HOST` + path, never rewritten. That is the point of storing a path instead of a URL.

- [ ] **Step 4: Run tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/models/entry_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/entry.rb test/models/entry_test.rb
git commit -m "R2-aware entry image read path

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Reuse rules — site-wide og:image and same-feed repeats

Two candidate filters for meta-derived urls, behind `IMAGE_REUSE_RULES`: skip a candidate that matches the host's root-page og:image, and skip one already used by another entry in the same feed (by URL before download, by content fingerprint after processing).

**Files:**
- Create: `app/jobs/image_crawler/lib/root_meta_image.rb`
- Create: `app/jobs/image_crawler/lib/reuse_rules.rb`
- Modify: `app/jobs/image_crawler/lib/meta_images.rb` (extract `parse_meta_urls`)
- Modify: `app/jobs/image_crawler/pipeline/find.rb` (skip hook in `attempt_unified`)
- Modify: `app/jobs/image_crawler/pipeline/process.rb` (fingerprint check before Upload)
- Test: `test/jobs/image_crawler/root_meta_image_test.rb` (new)
- Test: `test/jobs/image_crawler/reuse_rules_test.rb` (new)
- Test: `test/jobs/image_crawler/pipeline/find_test.rb`, `test/jobs/image_crawler/pipeline/process_test.rb`

**Interfaces:**
- Consumes: `meta_image_urls`/`page_url`/`feed_id` payload attributes (Task 8), `ImageCrawler::Cache` (existing Redis wrapper), `::Image.entry_images` + `::Image.url_fingerprint_for` (Task 2), `Process#requeue_remaining` (Task 5).
- Produces:
  - `MetaImages.parse_meta_urls(html, base_url) → [Addressable::URI]` — extracted from the existing `parse`, behavior identical.
  - `RootMetaImage.site_wide?(candidate_url, page_url) → bool` — true when `candidate_url` equals an og/twitter image of `page_url`'s host root page. False when `page_url` is blank/unparseable or is itself the root page. Root page results cached in Redis for 7 days (empty results cached too; fetch failures cached as empty).
  - `ReuseRules.enabled? → bool` (`ENV["IMAGE_REUSE_RULES"]` present).
  - `ReuseRules#skip?(url) → bool` — meta-derived candidates only; site-wide OR already used in feed by URL.
  - `ReuseRules#fingerprint_used_in_feed?(fingerprint) → bool` — meta-derived current candidate only; another entry in the feed has a row with this `image_fingerprint`.

- [ ] **Step 1: Extract `parse_meta_urls` from `MetaImages`**

In `app/jobs/image_crawler/lib/meta_images.rb`, replace `parse` with:

```ruby
    def self.parse_meta_urls(html, base_url)
      Nokogiri.HTML5(html).search("meta[property='twitter:image'], meta[property='og:image']").map do |element|
        url = element["content"]&.strip
        next if url.blank?
        Addressable::URI.join(base_url, url)
      end.compact
    end

    def parse(file)
      self.class.parse_meta_urls(file.read, parsed_url)
    end
```

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/meta_images_test.rb`
Expected: PASS (pure extraction).

- [ ] **Step 2: Write the failing `RootMetaImage` tests**

Create `test/jobs/image_crawler/root_meta_image_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  class RootMetaImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    def stub_root(body)
      stub_request(:get, "http://example.com/").to_return(status: 200, body: body, headers: {content_type: "text/html"})
    end

    test "detects a site-wide og:image" do
      stub_root %(<html><head><meta property="og:image" content="/site-wide.jpg"></head></html>)

      assert RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article")
      refute RootMetaImage.site_wide?("http://example.com/article-specific.jpg", "http://example.com/article")
    end

    test "never flags the root page's own image" do
      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/")
      assert_not_requested :get, "http://example.com/"
    end

    test "caches the root page lookup" do
      stub_root %(<html><head><meta property="og:image" content="/site-wide.jpg"></head></html>)

      2.times { RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article") }
      assert_requested :get, "http://example.com/", times: 1
    end

    test "caches failures as empty" do
      stub_request(:get, "http://example.com/").to_return(status: 500)

      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/article")
      refute RootMetaImage.site_wide?("http://example.com/site-wide.jpg", "http://example.com/other")
      assert_requested :get, "http://example.com/", times: 1
    end

    test "handles missing page context" do
      refute RootMetaImage.site_wide?("http://example.com/a.jpg", nil)
      refute RootMetaImage.site_wide?("http://example.com/a.jpg", "")
    end
  end
end
```

- [ ] **Step 3: Run to verify failure, then implement `RootMetaImage`**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/root_meta_image_test.rb`
Expected: FAIL — `NameError: uninitialized constant ImageCrawler::RootMetaImage`

Create `app/jobs/image_crawler/lib/root_meta_image.rb`:

```ruby
module ImageCrawler
  # An og:image that a host serves for its root page is site branding, not
  # article art. Candidates matching it are skipped so every entry in a feed
  # does not end up with the same generic image.
  class RootMetaImage
    CACHE_TTL = 7 * 24 * 60 * 60

    def self.site_wide?(candidate_url, page_url)
      new(page_url).site_wide?(candidate_url)
    end

    def initialize(page_url)
      @page_url = begin
        parsed = Addressable::URI.heuristic_parse(page_url.to_s)
        parsed&.host.nil? ? nil : parsed
      rescue Addressable::URI::InvalidURIError
        nil
      end
    end

    def site_wide?(candidate_url)
      return false if @page_url.nil?
      return false if root_page?
      root_urls.include?(candidate_url.to_s)
    end

    private

    def root_page?
      ["", "/"].include?(@page_url.path.to_s) && @page_url.query.nil?
    end

    def root_urls
      cached = Cache.read(cache_key)
      return cached[:urls] || [] if cached[:checked]

      urls = download
      Cache.write(cache_key, {checked: true, urls: urls}, options: {expires_in: CACHE_TTL})
      urls
    end

    def download
      file = Down.download(root_url, max_size: 5 * 1024 * 1024)
      MetaImages.parse_meta_urls(file.read, root_url).map(&:to_s)
    rescue Down::Error
      []
    end

    def root_url
      @root_url ||= Addressable::URI.new(scheme: @page_url.scheme || "https", host: @page_url.host).to_s
    end

    def cache_key
      "root_meta_image_#{Digest::SHA1.hexdigest(@page_url.host)}"
    end
  end
end
```

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/root_meta_image_test.rb`
Expected: PASS (5 tests)

- [ ] **Step 4: Write the failing `ReuseRules` tests**

Create `test/jobs/image_crawler/reuse_rules_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  class ReuseRulesTest < ActiveSupport::TestCase
    setup do
      flush_redis
      # skip? falls through to the site-wide check (a root-page fetch)
      # whenever the feed check misses; give every test a quiet root page.
      # Tests about the site-wide rule override this stub.
      stub_request(:get, "http://example.com/")
        .to_return(status: 200, body: "<html></html>", headers: {content_type: "text/html"})
      @url = "http://example.com/og.jpg"
      @image = Image.new_with_attributes(
        id: SecureRandom.hex,
        preset_name: "primary",
        image_urls: [],
        provider: ::Image.providers[:entry_preview],
        provider_id: 2,
        feed_id: 9,
        page_url: "http://example.com/article",
        meta_image_urls: [@url],
        original_url: @url
      )
    end

    def seed_row(provider_id:, feed_id: 9, url: @url, image_fingerprint: SecureRandom.hex(16))
      ::Image.create!(
        provider: :entry_preview,
        provider_id: provider_id.to_s,
        feed_id: feed_id,
        url: url,
        image_fingerprint: image_fingerprint,
        storage_path: ::Image.storage_path_for(url),
        width: 542, height: 304, bytesize: 12_345,
        placeholder_color: "aabbcc"
      )
    end

    test "disabled without the env flag" do
      seed_row(provider_id: 1)
      refute ReuseRules.new(@image).skip?(@url)
    end

    test "skips a url already used by another entry in the feed" do
      with_env("IMAGE_REUSE_RULES" => "1") do
        rules = ReuseRules.new(@image)
        refute rules.skip?(@url)

        seed_row(provider_id: 1)
        assert rules.skip?(@url)
      end
    end

    test "does not skip for the same entry, another feed, or non-meta candidates" do
      with_env("IMAGE_REUSE_RULES" => "1") do
        seed_row(provider_id: 2)
        refute ReuseRules.new(@image).skip?(@url), "an entry must not block itself on re-crawl"

        ::Image.delete_all
        seed_row(provider_id: 1, feed_id: 10)
        refute ReuseRules.new(@image).skip?(@url), "reuse is scoped per feed"

        ::Image.delete_all
        seed_row(provider_id: 1)
        @image.meta_image_urls = []
        refute ReuseRules.new(@image).skip?(@url), "inline img/media candidates are exempt"
      end
    end

    test "skips a site-wide og:image" do
      with_env("IMAGE_REUSE_RULES" => "1") do
        stub_request(:get, "http://example.com/")
          .to_return(status: 200, body: %(<meta property="og:image" content="/og.jpg">), headers: {content_type: "text/html"})

        assert ReuseRules.new(@image).skip?(@url)
      end
    end

    test "detects a repeated content fingerprint in the feed" do
      with_env("IMAGE_REUSE_RULES" => "1") do
        fingerprint = SecureRandom.hex(16)
        seed_row(provider_id: 1, url: "http://example.com/different-url.jpg", image_fingerprint: fingerprint)

        assert ReuseRules.new(@image).fingerprint_used_in_feed?(fingerprint)
        refute ReuseRules.new(@image).fingerprint_used_in_feed?(SecureRandom.hex(16))
      end
    end
  end
end
```

- [ ] **Step 5: Run to verify failure, then implement `ReuseRules`**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/reuse_rules_test.rb`
Expected: FAIL — `NameError: uninitialized constant ImageCrawler::ReuseRules`

Create `app/jobs/image_crawler/lib/reuse_rules.rb`:

```ruby
module ImageCrawler
  # Rejects boilerplate preview candidates. Only meta-derived candidates
  # (og:image / twitter:image) are policed — inline images and attached media
  # legitimately repeat within a feed (retweet chains, reposts).
  class ReuseRules
    def self.enabled?
      ENV["IMAGE_REUSE_RULES"].present?
    end

    def initialize(image)
      @image = image
    end

    # Pre-download check: another entry in this feed already uses the
    # candidate url, or it is the host's site-wide og:image. The feed check
    # runs first — it is one indexed query, while the site-wide check may
    # fetch the host's root page.
    def skip?(original_url)
      return false unless self.class.enabled?
      return false unless meta_candidate?(original_url)

      used_in_feed?(original_url) || site_wide?(original_url)
    end

    # Post-process check: same image bytes (different url) already used by
    # another entry in this feed. Catches cache-busted site-wide images.
    def fingerprint_used_in_feed?(fingerprint)
      return false unless self.class.enabled?
      return false unless meta_candidate?(@image.original_url)
      return false if @image.feed_id.nil?

      ::Image.entry_images
        .where(feed_id: @image.feed_id, image_fingerprint: fingerprint)
        .where.not(provider_id: @image.provider_id.to_s)
        .exists?
    end

    private

    def meta_candidate?(url)
      (@image.meta_image_urls || []).include?(url.to_s)
    end

    def site_wide?(url)
      RootMetaImage.site_wide?(url, @image.page_url)
    end

    def used_in_feed?(url)
      return false if @image.feed_id.nil?

      ::Image.entry_images
        .where(feed_id: @image.feed_id, url_fingerprint: ::Image.url_fingerprint_for(url))
        .where.not(provider_id: @image.provider_id.to_s)
        .exists?
    end
  end
end
```

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/reuse_rules_test.rb`
Expected: PASS (5 tests)

- [ ] **Step 6: Wire the pre-download check into `Find`**

In `app/jobs/image_crawler/pipeline/find.rb`, add at the top of `attempt_unified`:

```ruby
      def attempt_unified(original_url)
        if reuse_rules.skip?(original_url)
          Librato.increment("image.reuse_skipped")
          Sidekiq.logger.info @image.trace(message: "skipping reused image", metadata: {original_url: original_url})
          return false
        end

        download_cache = DownloadCache.new(original_url, @image)
        # ... rest unchanged
```

And add the memo next to the other private methods:

```ruby
      def reuse_rules
        @reuse_rules ||= ReuseRules.new(@image)
      end
```

Add a Find test to `test/jobs/image_crawler/pipeline/find_test.rb`:

```ruby
      def test_should_skip_reused_meta_candidate_and_try_the_next_url
        with_env("R2_BUCKET_IMAGES" => "images-test", "IMAGE_REUSE_RULES" => "1") do
          reused_url = "http://example.com/og.jpg"
          fresh_url = "http://example.com/inline.jpg"

          ::Image.create!(
            provider: :entry_preview, provider_id: "1", feed_id: 9,
            url: reused_url, image_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.storage_path_for(reused_url),
            width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc",
            data: {"legacy_storage_url" => "https://bucket.s3.amazonaws.com/abc/abcdef.jpg"}
          )
          stub_request_file("image.jpeg", fresh_url, headers: {content_type: "image/jpeg"})

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "primary",
            image_urls: [reused_url, fresh_url],
            provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9,
            page_url: "http://example.com/article", meta_image_urls: [reused_url]
          )
          Find.new.perform(image.to_h)

          refute_requested :get, reused_url
          assert_requested :get, fresh_url
          assert_equal 1, Process.jobs.size
        end
      end
```

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/find_test.rb`
Expected: PASS

- [ ] **Step 7: Wire the post-process fingerprint check into `Process`**

In `app/jobs/image_crawler/pipeline/process.rb`, replace the `Upload.perform_async(@image.to_h)` line with:

```ruby
          if reuse_rejected?
            Librato.increment("image.reuse_rejected")
            Sidekiq.logger.info "Process: rejecting reused fingerprint public_id=#{@image.id} original_url=#{@image.original_url}"
            discard_processed_files
            requeue_remaining
          else
            Upload.perform_async(@image.to_h)
          end
```

And add the private methods:

```ruby
      def reuse_rejected?
        return false unless @image.unified?
        ReuseRules.new(@image).fingerprint_used_in_feed?(@image.fingerprint)
      end

      def discard_processed_files
        [@image.processed_path, @image.webp_path].compact.each do |path|
          File.unlink(path) rescue Errno::ENOENT
        end
      end
```

Add a Process test to `test/jobs/image_crawler/pipeline/process_test.rb`:

```ruby
      def test_should_reject_repeated_fingerprint_in_feed
        with_env("R2_BUCKET_IMAGES" => "images-test", "IMAGE_REUSE_RULES" => "1") do
          # Compute the fingerprint this exact source produces.
          reference = Processor::Cropper.new(copy_support_file("image.jpeg"), crop: :smart_crop, extension: "jpeg", width: 542, height: 304).crop_pair!
          fingerprint = reference[:webp].fingerprint
          File.unlink(reference[:jpg].file)
          File.unlink(reference[:webp].file)

          original_url = "http://example.com/cache-busted.jpg?v=2"
          ::Image.create!(
            provider: :entry_preview, provider_id: "1", feed_id: 9,
            url: "http://example.com/cache-busted.jpg?v=1",
            image_fingerprint: fingerprint,
            storage_path: ::Image.storage_path_for("http://example.com/cache-busted.jpg?v=1"),
            width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc"
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "primary",
            image_urls: ["http://example.com/next-candidate.jpg"],
            provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9,
            page_url: "http://example.com/article", meta_image_urls: [original_url],
            original_url: original_url, final_url: original_url,
            download_path: copy_support_file("image.jpeg"), original_extension: "jpeg"
          )

          assert_no_difference -> { Upload.jobs.size } do
            assert_difference -> { FindCritical.jobs.size }, +1 do
              Process.new.perform(image.to_h)
            end
          end

          requeued = Image.new(FindCritical.jobs.last["args"].first)
          assert_equal ["http://example.com/next-candidate.jpg"], requeued.image_urls
          assert_equal 9, requeued.feed_id
        end
      end
```

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/process_test.rb`
Expected: PASS

- [ ] **Step 8: Run the whole image crawler suite**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_crawler`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add app/jobs/image_crawler/lib/root_meta_image.rb app/jobs/image_crawler/lib/reuse_rules.rb app/jobs/image_crawler/lib/meta_images.rb app/jobs/image_crawler/pipeline/find.rb app/jobs/image_crawler/pipeline/process.rb test/jobs/image_crawler
git commit -m "Reuse rules: skip site-wide og:images and same-feed repeats

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Refcounted garbage collection

`ImageGarbageCollector` deletes usage rows for deleted entries and removes the shared R2 object when the last reference goes, under the same advisory lock `Dedupe`/`create_image` take. `EntryDeleter` also starts deleting legacy link-preview objects (today they leak forever).

**Files:**
- Create: `app/jobs/image_garbage_collector.rb`
- Modify: `app/jobs/entry_deleter.rb`
- Test: `test/jobs/image_garbage_collector_test.rb` (new)
- Test: `test/jobs/entry_deleter_test.rb`

**Interfaces:**
- Consumes: `::Image.entry_images`, `::Image.with_url_lock` (Task 2), `STORAGE_R2` (Task 3), rows written by Tasks 6–7.
- Produces:
  - `ImageGarbageCollector.perform(entry_ids)` — Sidekiq worker, `utility` queue.
  - `EntryDeleter` enqueues it with the deleted entry ids and passes legacy link-preview urls to `ImageDeleter`.

- [ ] **Step 1: Write the failing GC tests**

Create `test/jobs/image_garbage_collector_test.rb`:

```ruby
require "test_helper"

class ImageGarbageCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @url = "http://example.com/shared.jpg"
  end

  def seed_row(provider_id:, url: @url)
    Image.create!(
      provider: :entry_preview,
      provider_id: provider_id.to_s,
      feed_id: 9,
      url: url,
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for(url),
      width: 542, height: 304, bytesize: 12_345,
      placeholder_color: "aabbcc"
    )
  end

  test "keeps the object while other entries reference it" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      seed_row(provider_id: 2)

      delete = stub_request(:delete, /r2\.cloudflarestorage\.com/)

      assert_difference -> { Image.count }, -1 do
        ImageGarbageCollector.new.perform([1])
      end

      assert_not_requested delete
      assert Image.exists?(provider_id: "2")
    end
  end

  test "deletes the object with the last reference" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      row = seed_row(provider_id: 1)
      delete = stub_request(:delete, "https://test-account.r2.cloudflarestorage.com/images-test/#{row.storage_path}")

      ImageGarbageCollector.new.perform([1])

      assert_requested delete
      assert_equal 0, Image.count
    end
  end

  test "handles entries with both providers and multiple fingerprints" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      seed_row(provider_id: 1)
      other = seed_row(provider_id: 2, url: "http://example.com/other.jpg")
      Image.create!(
        provider: :entry_link_preview, provider_id: "1", feed_id: 9,
        url: "http://example.com/linked.jpg",
        image_fingerprint: SecureRandom.hex(16),
        storage_path: Image.storage_path_for("http://example.com/linked.jpg"),
        width: 542, height: 304, bytesize: 1, placeholder_color: "aabbcc"
      )

      stub_request(:delete, /r2\.cloudflarestorage\.com/)

      ImageGarbageCollector.new.perform([1])

      assert_equal [other.id], Image.pluck(:id)
    end
  end

  test "does nothing without rows" do
    ImageGarbageCollector.new.perform([12345])
  end
end
```

- [ ] **Step 2: Run to verify failure, then implement**

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_garbage_collector_test.rb`
Expected: FAIL — `NameError: uninitialized constant ImageGarbageCollector`

Create `app/jobs/image_garbage_collector.rb`:

```ruby
# Removes images-table usage rows for deleted entries and deletes the shared
# R2 object once nothing references it. The advisory lock serializes the
# zero-reference check against Dedupe/create_image attaching a new reference
# to the same object.
class ImageGarbageCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    rows = Image.entry_images.where(provider_id: entry_ids).to_a
    return if rows.empty?

    rows.group_by(&:url_fingerprint).each do |fingerprint, group|
      Image.with_url_lock(fingerprint) do
        Image.where(id: group.map(&:id)).delete_all
        unless Image.entry_images.where(url_fingerprint: fingerprint).exists?
          delete_object(group.first.storage_path)
        end
      end
    end

    Librato.increment("image.gc_rows", by: rows.size)
  end

  def delete_object(path)
    return if ENV["R2_BUCKET_IMAGES"].blank?
    Fog::Storage.new(STORAGE_R2).delete_object(ENV["R2_BUCKET_IMAGES"], path)
    Librato.increment("image.gc_objects")
  rescue Excon::Error::NotFound
  end
end
```

Known residual race, accepted: if `Upload` PUTs a fresh object and GC deletes that same fingerprint's last old row in the window before `create_image` takes the lock, the fresh object is deleted and one entry holds a dead reference. The window is milliseconds, requires the same URL to be simultaneously re-crawled and last-pruned, and the entry self-heals on its next re-crawl (`FixImage`-style recovery also remains available).

Run: `source ~/.bash_profile && bin/rails test test/jobs/image_garbage_collector_test.rb`
Expected: PASS (4 tests)

- [ ] **Step 3: Write the failing EntryDeleter tests**

Append to the test class in `test/jobs/entry_deleter_test.rb`:

```ruby
  test "should enqueue image cleanup for deleted entries" do
    entry = @entries.first
    entry.update(
      published: 20.years.ago,   # oldest by published, guaranteed to be pruned
      image: {"processed_url" => "https://bucket.s3.amazonaws.com/abc/preview.jpg"},
      data: {
        "twitter_link_image_processed" => "https://bucket.s3.amazonaws.com/abc/link-legacy.jpg",
        "link_image" => {"processed_url" => "https://bucket.s3.amazonaws.com/abc/link-new.jpg"}
      }
    )

    EntryDeleter.new.perform(@feed.id)

    assert_equal 1, ImageGarbageCollector.jobs.size
    assert_includes ImageGarbageCollector.jobs.first["args"].first, entry.id

    deleted_urls = ImageDeleter.jobs.flat_map { _1["args"].first }
    assert_includes deleted_urls, "https://bucket.s3.amazonaws.com/abc/preview.jpg"
    assert_includes deleted_urls, "https://bucket.s3.amazonaws.com/abc/link-legacy.jpg"
    assert_includes deleted_urls, "https://bucket.s3.amazonaws.com/abc/link-new.jpg"
  end
```

(Setup creates more entries than `ENTRY_LIMIT`, and `bulk_create_entries` orders by published — `@entries.first` is the oldest, which gets pruned.)

- [ ] **Step 4: Run to verify failure, then implement EntryDeleter changes**

Run: `source ~/.bash_profile && bin/rails test test/jobs/entry_deleter_test.rb`
Expected: the new test FAILS (no GC job, link urls missing).

In `app/jobs/entry_deleter.rb`, replace `prune_entries` and `delete_entries`:

```ruby
  def prune_entries(feed_id, entry_limit)
    entry_count = Entry.where(feed_id: feed_id).count
    if entry_count > entry_limit
      entries_to_keep = Entry.where(feed_id: feed_id).order("published DESC").limit(entry_limit).pluck("entries.id")
      entries_to_delete = Entry.where(feed_id: feed_id, starred_entries_count: 0, recently_played_entries_count: 0)
        .where.not(id: entries_to_keep)
        .pluck(:id, :image, Arel.sql("data->>'twitter_link_image_processed'"), Arel.sql("data#>>'{link_image,processed_url}'"))
      entries_to_delete_ids = entries_to_delete.map(&:first)
      entries_to_delete_images = entries_to_delete.flat_map { |_, image, link_legacy, link_new|
        [image && image["processed_url"], link_legacy, link_new]
      }.compact
      delete_entries(feed_id, entries_to_delete_ids, entries_to_delete_images)
    end
  end

  def delete_entries(feed_id, entry_ids, images = [])
    entry_ids = [*entry_ids]

    if images.present?
      ImageDeleter.perform_async(images)
    end

    if entry_ids.present?
      Search::SearchIndexRemove.perform_async(entry_ids)

      ActiveRecord::Base.transaction do
        UnreadEntry.where(entry_id: entry_ids).delete_all
        UpdatedEntry.where(entry_id: entry_ids).delete_all
        RecentlyReadEntry.where(entry_id: entry_ids).delete_all
        RecentlyPlayedEntry.where(entry_id: entry_ids).delete_all
        StarredEntry.where(entry_id: entry_ids).delete_all
        Entry.where(id: entry_ids).delete_all
      end

      # After the transaction: if the deletes roll back, the usage rows must
      # survive too.
      ImageGarbageCollector.perform_async(entry_ids)

      Librato.increment("entry.destroy", by: entry_ids.count)
    end
  end
```

(The `Arel.sql` fragments are static strings — nothing is interpolated into them; both `->>`/`#>>` operate on the `json` column and return NULL for missing keys or NULL data.)

- [ ] **Step 5: Run the deleter tests to verify they pass**

Run: `source ~/.bash_profile && bin/rails test test/jobs/entry_deleter_test.rb test/jobs/image_garbage_collector_test.rb`
Expected: PASS — all pre-existing EntryDeleter tests plus the new ones.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_garbage_collector.rb app/jobs/entry_deleter.rb test/jobs/image_garbage_collector_test.rb test/jobs/entry_deleter_test.rb
git commit -m "Refcounted image GC; stop leaking link preview objects

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Full-suite verification and env documentation

**Files:**
- Modify: `.env.development`
- Test: entire suite

**Interfaces:**
- Consumes: everything above.
- Produces: green suite; documented env vars for other developers.

- [ ] **Step 1: Document the new env vars**

Append to `.env.development` (commented out — the features stay off in dev until opted into). NOTE: `.env.development` is gitignored — this edit is for the local machine only and must NOT be committed; the committed record of these vars is this plan and the design doc.

```bash
# Unified image storage on R2 (all optional; features are inert when unset)
# export R2_ACCESS_KEY_ID=
# export R2_SECRET_ACCESS_KEY=
# export R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
# export R2_REGION=auto
# export R2_BUCKET_IMAGES=            # presence enables webp dual-writes + image rows
# export R2_IMAGE_HOST=               # presence flips entry image reads to R2 (public bucket domain)
# export IMAGE_REUSE_RULES=           # presence enables site-wide/same-feed reuse rules
```

- [ ] **Step 2: Run the full test suite**

Run: `source ~/.bash_profile && bundle exec rake`
Expected: PASS. Note: piped test output is compressed to counts in this environment — if a failure appears, re-run the specific file with `bin/rails test <path>` to see details. If the suite dies with zero output, restart OrbStack and retry (known local flake).

- [ ] **Step 3: Fix anything the suite surfaces**

Likely candidates if something fails: tests that assert on exact `Pipeline::Find` payloads (now include `feed_id`/`page_url`/`meta_image_urls`), or fixtures hitting the new `images` table. Fix forward; do not weaken unrelated assertions.

- [ ] **Step 4: Commit the design and plan documents**

`.env.development` is gitignored — nothing to commit for it. Commit the design/plan docs instead so the branch carries its own record:

```bash
git add docs/superpowers/specs/2026-08-12-unified-image-storage-design.md docs/superpowers/plans/2026-08-12-unified-image-storage.md
git commit -m "Design and plan for unified image storage on R2

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Out of scope (deliberately)

- Backfill/migration of existing entries to R2 (future project; the schema anticipates it).
- Stopping the legacy S3 write / jpg encode (Phase 3 — after production bake).
- Migrating podcast/itunes/icon/favicon presets to R2.
- One-off sweep of already-leaked legacy link-preview objects on S3.
- Retiring `FixImage` / pointing it at R2.
- API/release-note communication that `cdn_url` will serve `.webp` after read cutover.
