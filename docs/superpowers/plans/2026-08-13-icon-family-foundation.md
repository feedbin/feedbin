# Icon Family Foundation (Phases A + B) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the shared image pipeline everything the icon family needs — content-addressed storage keyed by the original bytes, per-preset output formats, storage-path refcounting with a replacement-GC path, and the two icon presets — then move favicon and preview-image invalidation into the view cache digest so `TouchFeeds`' 100,000-row fan-out can be deleted.

**Architecture:** Two independent halves. **Phase A** extends `ImageCrawler`'s pipeline (`Pipeline::Find` → `Download` → `Pipeline::Process` → `Pipeline::Upload` → callback job) with a third preset mode: *content-addressed*. Unlike the unified entry presets, a content-addressed preset always downloads (icons mutate under a stable URL, so `Dedupe`'s skip-the-download shortcut is exactly wrong), fingerprints the **original** bytes, and short-circuits after the download when nothing changed — skipping processing, upload, and the row write. Its `storage_path` is derived from that fingerprint rather than from the URL, which makes the stored object the shared resource, so garbage collection and the advisory locks move from `url_fingerprint` to `storage_path`. **Phase B** puts the `Favicon` record and the entry's `Image` record into `entries_cache_key`, so one row update invalidates every view referencing it at any scale, and deletes `Favicon#touch_owners`/`TouchFeeds`.

**Tech Stack:** Rails 8.1, Sidekiq, Fog::Storage (AWS provider; R2 is S3-compatible), libvips via ImageProcessing::Vips, Postgres (advisory locks, `uuid` columns), Redis, minitest + webmock.

**Design doc:** `docs/superpowers/specs/2026-08-13-icon-family-design.md` (this plan covers Phases A and B only; the tenant migrations C–E get their own plans)

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`. A single test: `bin/rails test <path> -n <name>`.
- NEVER interpolate values into SQL strings — use hash conditions, binds, or `sanitize_sql_array`.
- **No tenant moves in this plan.** No favicon, podcast, YouTube, or apple-touch-icon source changes where it writes. `FaviconCrawler::Finder` keeps writing the `favicons` table and its S3 bucket exactly as today. The icon presets are registered and exercised by tests, but no production caller schedules them yet.
- **Do not change behavior for existing presets.** `primary`, `twitter`, `youtube` keep 542×304 WebP q58 + jpg q80. `podcast`, `podcast_feed` keep 200×200 jpg. `icon` (remote_file) keeps `limit_crop`'s alpha-driven png/jpg choice. Their existing tests must stay green.
- **MD5, not SHA1**, for every new fingerprint: 128 bits fits the `uuid` columns this table already uses. Always `Digest::MD5.file(path).hexdigest` — never `Digest::MD5.hexdigest(File.read(path))` — so the file streams through the digest in C instead of allocating the whole image as a Ruby string.
- **The touch rule governs.** An `images` row's `updated_at` may change only when the stored bytes actually change, because after Phase B it is a view cache key. No unconditional `touch`, no "record that we checked" write. Two tasks below test this explicitly.
- All pipeline jobs remain `retry: false`.
- Icon output is PNG with `strip: true` and `resize_to_limit` (never `resize_to_fit`) — upscaling fabricates no detail.
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## Deployment notes

`Pipeline::Process`/`Pipeline::Upload` run on host-local queues (`local_queue` appends the hostname) on dedicated crawler machines; deploys are not atomic across hosts and every job is `retry: false`. `ImageCrawler::Image#initialize` already ignores unknown payload attributes, so adding `original_fingerprint` to `ATTRIBUTES` (Task 5) is safe to deploy mid-flight: an older consumer drops the attribute, and since no production caller uses a content-addressed preset in this plan, nothing depends on it.

Phase B changes cache keys (`v7` → `v8` for entries, `v3` → `v4` and `v9` → `v10` for the sidebar). Expect one cold-cache render wave after deploy; that is the intended cost of the version bump and is why the bumps are deliberate rather than incidental.

---

# Phase A — Pipeline foundation

### Task 1: `storage_path_for` takes an extension; output format becomes a preset property

`Image.storage_path_for` hardcodes `.webp`, and `ImageCrawler::Image#r2_storage_options` hardcodes `image/webp`. The icon family stores PNG (alpha, and the ICO best-layer logic depends on it). Make the extension an argument fed by a new preset property.

**Files:**
- Modify: `app/models/image.rb` (`storage_path_for`, lines 38–41)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`PRESETS`, `storage_path`, `r2_storage_options`)
- Test: `test/models/image_test.rb`, `test/jobs/image_crawler/image_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Image.storage_path_for(url, variant, extension = "webp") -> String` — third positional argument, defaulted so every existing call site is unchanged.
  - `Image.path_for(fingerprint, extension) -> String` — the shared shard-and-name helper.
  - `ImageCrawler::Image::PRESETS[*][:format]` — a String naming the stored object's file extension (`"webp"` for the unified entry presets, `"jpg"` for the podcast presets).
  - `ImageCrawler::Image::CONTENT_TYPES` — `{"webp" => "image/webp", "png" => "image/png", "jpg" => "image/jpeg"}`.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/image_test.rb`:

```ruby
  test "storage_path_for defaults to webp and accepts an extension" do
    fingerprint = Image.url_fingerprint_for("http://example.com/a.jpg", "32x32")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.webp"),
      Image.storage_path_for("http://example.com/a.jpg", "32x32")
    assert_equal File.join(fingerprint[0..2], "#{fingerprint}.png"),
      Image.storage_path_for("http://example.com/a.jpg", "32x32", "png")
  end
```

Append to `test/jobs/image_crawler/image_test.rb` (inside `module ImageCrawler; class ImageTest`):

```ruby
    test "storage_path and content type follow the preset format" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg"
      )
      assert_equal "webp", image.preset.format
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304", "webp"), image.storage_path
      assert_equal "image/webp", image.r2_storage_options["Content-Type"]
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: FAIL — `wrong number of arguments (given 3, expected 2)` on `storage_path_for`, and `nil` for `preset.format`.

- [ ] **Step 3: Add the extension argument**

In `app/models/image.rb`, replace `storage_path_for`:

```ruby
  # The extension is the stored object's format, which is a property of the
  # preset: webp for entry previews, png for the icon family (alpha, and the
  # ICO best-layer logic depends on it).
  def self.storage_path_for(url, variant, extension = "webp")
    path_for(url_fingerprint_for(url, variant), extension)
  end

  def self.path_for(fingerprint, extension)
    File.join(fingerprint[0..2], "#{fingerprint}.#{extension}")
  end
```

- [ ] **Step 4: Make the format a preset property**

In `app/jobs/image_crawler/lib/image.rb`, add `format:` to each existing preset — `primary`, `twitter`, `youtube` get `format: "webp"`; `podcast`, `podcast_feed` get `format: "jpg"`; leave `icon` alone (its `limit_crop` picks png or jpg from the source's alpha channel, and it never writes to R2). For example, `primary` becomes:

```ruby
      primary: {
        width: 542,
        height: 304,
        minimum_size: 20_000,
        crop: :smart_crop,
        format: "webp",
        validate: true,
        unified: true,
        job_class: EntryImage
      },
```

Then, in the same file, add the content-type map next to `BUCKET`:

```ruby
    CONTENT_TYPES = {
      "webp" => "image/webp",
      "png"  => "image/png",
      "jpg"  => "image/jpeg"
    }.freeze
```

and replace `storage_path` and `r2_storage_options`:

```ruby
    def storage_path
      ::Image.storage_path_for(original_url, variant, preset.format)
    end
```

```ruby
    def r2_storage_options
      {
        "Content-Type"  => CONTENT_TYPES.fetch(preset.format),
        "Cache-Control" => "max-age=315360000, public, immutable"
      }
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/pipeline test/jobs/image_garbage_collector_test.rb
```

Expected: PASS. The pipeline and GC tests prove the defaulted third argument left every existing call site alone.

- [ ] **Step 6: Commit**

```bash
git add app/models/image.rb app/jobs/image_crawler/lib/image.rb test/models/image_test.rb test/jobs/image_crawler/image_test.rb && git commit -m "Make the stored object's extension a preset property

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: WITHDRAWN — superseded during execution

`Cropper#crop!` was going to take a `format:` keyword fed by `preset.format`.
That was wrong: `preset.format` is the **stored R2 object's** extension
(`"webp"` for the entry presets), while `crop!` writes the **legacy S3**
output, which is jpg. They only coincide for the icon presets, which have a
single output.

`crop_pair!` runs only when `unified?` is true, which requires
`R2_BUCKET_IMAGES` to be set. With R2 unconfigured, `primary`/`twitter`/
`youtube` fall through to `crop!` — so threading `preset.format` there made
them write webp to legacy S3, changing behavior for existing presets and
breaking `FindTest#test_should_copy_image` and
`ProcessTest#test_should_enqueue_upload`.

**Resolution (owner's call): the output format stays a property of the
strategy, not the preset.** `crop!` already special-cases `limit_crop` with
an early return; Task 4's `icon_crop` gets the same treatment and saves its
own PNG. `preset.format` keeps its Task 1 meaning — the stored object's
extension, read only by `storage_path` and `r2_storage_options`, both of
which are R2-only paths. No `format:` keyword, no `SAVERS` table, and
`Task 1` needs no amendment.

Nothing to implement here. `PNG_SAVER` and the `crop!` early return moved
into Task 4.

### Task 3: Extract `Processor::IconLayer`

`FaviconCrawler::Image#best_layer` picks the largest ICO layer whose average colour is not nil / transparent-black / white. The legacy crawler keeps running throughout the migration, so the new preset must **call** that logic, not copy it — a fork guarantees the two drift.

**Files:**
- Create: `app/jobs/image_crawler/lib/processor/icon_layer.rb`
- Modify: `app/jobs/favicon_crawler/image.rb`
- Test: `test/jobs/image_crawler/processor/icon_layer_test.rb` (new file)

**Interfaces:**
- Consumes: nothing.
- Produces: `ImageCrawler::Processor::IconLayer.best(path) -> Vips::Image | nil` — the best layer of a multi-layer icon, or `nil` when every layer is blank/white/transparent. `IconLayer::INVALID_COLORS` — the array of rejection lambdas, moved verbatim.

- [ ] **Step 1: Write the failing test**

Create `test/jobs/image_crawler/processor/icon_layer_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  module Processor
    class IconLayerTest < ActiveSupport::TestCase
      def test_should_pick_the_largest_usable_layer
        layer = IconLayer.best(support_file("favicon.ico"))

        assert_not_nil layer
        assert_operator layer.width, :>=, 16
      end

      # A favicon whose every layer is blank is not a favicon. Returning nil
      # here is what lets the crawler move on to the next candidate instead of
      # storing an empty square.
      def test_should_return_nil_when_every_layer_is_blank
        assert_nil IconLayer.best(support_file("favicon-blank.ico"))
      end

      def test_should_return_nil_for_a_file_vips_cannot_open
        path = File.join(Dir.tmpdir, SecureRandom.hex)
        File.binwrite(path, "not an image at all")

        assert_nil IconLayer.best(path)
      ensure
        FileUtils.rm_f path
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/icon_layer_test.rb
```

Expected: FAIL with `uninitialized constant ImageCrawler::Processor::IconLayer`.

- [ ] **Step 3: Create the extracted class**

Create `app/jobs/image_crawler/lib/processor/icon_layer.rb`:

```ruby
module ImageCrawler
  module Processor
    # Picks the layer to render out of a multi-layer icon source. An .ico
    # carries several sizes; the largest is the one worth scaling, but plenty
    # of sites ship a large layer that is blank, transparent black, or solid
    # white padding around a smaller real icon. Reject those and take the
    # largest of what is left.
    #
    # Shared deliberately: FaviconCrawler::Image keeps running through the
    # whole icon migration, and a forked copy of these heuristics would drift
    # from the one the new presets use.
    class IconLayer
      INVALID_COLORS = [
        -> (color) { color.nil? },
        -> (color) { color == "00000000" },        # opacity bit matters for black
        -> (color) { color.start_with?("ffffff") } # ignore opacity bit for white because the result is white
      ]

      # Returns a Vips::Image, or nil when nothing in the source is usable.
      def self.best(path)
        new(path).best
      end

      def initialize(path)
        @path = path
      end

      def best
        (0..4)
          .filter_map { load_layer(it) }
          .uniq       { it.size }
          .sort_by    { it.size.first * -1 }
          .find       { |layer|
            !INVALID_COLORS.any? { |proc| proc.call(color(layer)) }
          }
      end

      private

      def load_layer(page)
        begin
          Vips::Image.new_from_file(@path, page: page)
        rescue Vips::Error
          Vips::Image.new_from_file(@path)
        end
      rescue Vips::Error
        nil
      end

      def color(source)
        hex = nil
        file = ImageProcessing::Vips
          .source(source)
          .resize_to_fill(1, 1, sharpen: false)
          .custom { |image|
            image.tap do |data|
              hex = data.getpoint(0, 0).first(3).map { "%02x" % it }.join
            end
          }
          .call
        file.unlink
        hex
      end
    end
  end
end
```

- [ ] **Step 4: Point the legacy crawler at it**

Replace the whole of `app/jobs/favicon_crawler/image.rb` with:

```ruby
module FaviconCrawler
  class Image
    def self.resize(*args)
      new(*args).resize
    end

    def resize
      return unless ImageFormat.allowed?(@path)

      image = ImageCrawler::Processor::IconLayer.best(@path)

      return unless image.present?

      ImageProcessing::Vips
        .source(image)
        .resize_to_fit(32, 32)
        .saver(strip: true)
        .convert("png")
        .call
    end

    private

    def initialize(path)
      @path = path
    end
  end
end
```

Note `resize_to_fit` stays here: this is the legacy crawler, and changing its output would change every stored favicon. The new preset uses `resize_to_limit` (Task 4).

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/icon_layer_test.rb test/jobs/favicon_crawler/finder_test.rb
```

Expected: PASS, including the legacy crawler's "should skip blank favicon" test, which is the extraction's real proof.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/lib/processor/icon_layer.rb app/jobs/favicon_crawler/image.rb test/jobs/image_crawler/processor/icon_layer_test.rb && git commit -m "Extract the icon best-layer selection so both crawlers share it

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `icon_crop` strategy and the two icon presets

Add the rendering recipe the icon family uses — best layer, `resize_to_limit`, PNG — and register the `favicon` (32×32) and `touch_icon` (200×200) presets on it.

**Files:**
- Modify: `app/jobs/image_crawler/lib/processor/cropper.rb`
- Modify: `app/jobs/image_crawler/lib/image.rb` (`PRESETS`, `send_to_feedbin`)
- Test: `test/jobs/image_crawler/processor/cropper_test.rb`, `test/jobs/image_crawler/image_test.rb`

**Interfaces:**
- Consumes: `IconLayer.best` (Task 3).
- Produces:
  - `Cropper::PNG_SAVER = {strip: true}`.
  - `Cropper#icon_crop -> Processed` — a strategy method with its own early return in `crop!`, mirroring the `limit_crop` branch that is already there. It returns a saved `Processed`, not a pipeline, and never reads any caller-supplied format: PNG is a property of this recipe.
  - `Cropper#best_layer -> Vips::Image | nil`, memoized including the nil case.
  - `PRESETS[:favicon]` = `{width: 32, height: 32, minimum_size: nil, crop: :icon_crop, format: "png", validate: false, unified: true, content_addressed: true, legacy_store: false, job_class: nil}`.
  - `PRESETS[:touch_icon]` = the same with `width: 200, height: 200`.
  - `ImageCrawler::Image#variant` returns `"32x32"` / `"200x200"` for them (unchanged code, newly pinned by test).

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/processor/cropper_test.rb`:

```ruby
      def test_should_render_an_icon_as_png_from_the_best_layer
        file = copy_support_file("favicon.ico")
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 32, height: 32)

        assert cropper.valid?(false)
        image = cropper.crop!

        assert_equal(:png, ImageFormat.detect(image.file))
        assert_operator image.width, :<=, 32
        assert_operator image.height, :<=, 32
        FileUtils.rm image.file
      end

      # limit, not fit: upscaling fabricates no detail, it only makes a bigger
      # file that is equally soft. A 200x200 recipe applied to a small source
      # must leave the source's dimensions alone.
      def test_should_never_upscale_an_icon
        file = copy_support_file("favicon.ico")
        layer_width = IconLayer.best(file).width

        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 200, height: 200)
        image = cropper.crop!

        assert_operator layer_width, :<, 200, "fixture must be smaller than the target for this to prove anything"
        assert_equal layer_width, image.width
        FileUtils.rm image.file
      end

      # Plenty of sites now ship an SVG favicon. It rasterizes at the preset's
      # size like any other input -- one rendition per variant, no format
      # branch -- which also proves librsvg is reachable through vips.
      def test_should_rasterize_an_svg_icon
        file = File.join(Dir.tmpdir, "#{SecureRandom.hex}.svg")
        File.write(file, %(<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" fill="#0867e2"/></svg>))

        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "svg", width: 32, height: 32)
        assert cropper.valid?(false)
        image = cropper.crop!

        assert_equal(:png, ImageFormat.detect(image.file))
        assert_equal(32, image.width)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      def test_should_be_invalid_when_no_icon_layer_is_usable
        file = copy_support_file("favicon-blank.ico")
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "ico", width: 32, height: 32)

        assert_not cropper.valid?(false)
      end
```

Append to `test/jobs/image_crawler/image_test.rb`:

```ruby
    # variant names the rendering recipe, not the result. A 180x180 touch icon
    # rendered by the 200x200 limit recipe stays 180x180 and is still variant
    # "200x200" -- keying on the actual output would fragment the namespace and
    # break dedup between two renditions of the same recipe.
    test "icon presets keep their recipe as the variant and store png" do
      %w[favicon touch_icon].zip(["32x32", "200x200"]).each do |preset_name, variant|
        image = Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: preset_name, image_urls: [],
          provider: ::Image.providers[:feed_icon], provider_id: 1,
          original_url: "http://example.com/favicon.ico",
          width: 17, height: 17
        )
        assert_equal variant, image.variant
        assert_equal "png", image.preset.format
        assert_equal "image/png", image.r2_storage_options["Content-Type"]
        assert_equal :icon_crop, image.preset.crop
      end
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/cropper_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: FAIL — `NoMethodError: undefined method 'icon_crop'` from `crop!`'s `geometry` fallthrough (`send(:icon_crop)`), and `nil` for `image.preset.format`.

- [ ] **Step 3: Add the strategy to the Cropper**

In `app/jobs/image_crawler/lib/processor/cropper.rb`, add the PNG saver next to the existing `JPG_SAVER`/`WEBP_SAVER` constants:

```ruby
      # Icons are flat graphics with alpha; there is nothing to trade quality
      # against, so the only knob is dropping metadata.
      PNG_SAVER  = {strip: true}.freeze
```

Give `icon_crop` its own early return in `crop!`, alongside the `limit_crop` branch already there. PNG is a property of this recipe, not of the caller — `crop!` keeps writing jpg for every other strategy, which is what the legacy S3 object has always been:

```ruby
      def crop!
        return limit_crop if @crop == :limit_crop
        return icon_crop  if @crop == :icon_crop
        Processed.from_pipeline(save_as(geometry, "jpg", JPG_SAVER))
      end
```

Then add `best_layer` and `icon_crop` next to `limit_crop`:

```ruby
      # Multi-layer sources have no single "the image"; the layer choice is the
      # first real decision, so it happens before any resizing. Memoized
      # including the nil case -- ||= would re-run the whole layer scan every
      # time the answer was "nothing usable".
      def best_layer
        return @best_layer if defined?(@best_layer)
        @best_layer = IconLayer.best(ImageFormat.checked!(@file))
      end

      def icon_crop
        image = ImageProcessing::Vips
          .source(best_layer)
          .resize_to_limit(@width, @height)

        Processed.from_pipeline(save_as(image, "png", PNG_SAVER))
      end
```

and extend `valid?` so a source with no usable layer is rejected before `icon_crop` tries to build a pipeline from `nil`:

```ruby
      def valid?(validate)
        source.avg
        return false if @crop == :icon_crop && best_layer.nil?
        validate ? (source.width >= @width && source.height >= @height) : true
      rescue ::Vips::Error, ImageFormat::Unsupported
        false
      end
```

- [ ] **Step 4: Register the presets**

In `app/jobs/image_crawler/lib/image.rb`, add to `PRESETS` after `icon`:

```ruby
      favicon: {
        width: 32,
        height: 32,
        minimum_size: nil,
        crop: :icon_crop,
        format: "png",
        validate: false,
        unified: true,
        content_addressed: true,
        legacy_store: false,
        job_class: nil
      },
      touch_icon: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :icon_crop,
        format: "png",
        validate: false,
        unified: true,
        content_addressed: true,
        legacy_store: false,
        job_class: nil
      }
```

`validate: false` matters: a host shipping nothing larger than a 16×16 `favicon.ico` must still get a row, and `limit` never upscales it. `legacy_store: false` means one stored object, in R2 — the legacy favicon object already exists in its own bucket, written by the crawler that is still running.

In the same file, guard the callback so a preset without a tenant is inert rather than a `NoMethodError` on nil:

```ruby
    def send_to_feedbin(include_unified: true)
      # A preset with no callback job stores the row and stops. The icon
      # presets ship before their tenants do; each tenant adds its job_class
      # when it lands.
      return if preset.job_class.nil?

      payload = {
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/cropper_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/lib/processor/cropper.rb app/jobs/image_crawler/lib/image.rb test/jobs/image_crawler/processor/cropper_test.rb test/jobs/image_crawler/image_test.rb && git commit -m "Add the icon_crop strategy and the favicon/touch_icon presets

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `original_fingerprint` column and pipeline plumbing

The icon family's whole problem is new bytes at a stable URL, so identity has to come from the bytes. Add the column and compute it at download time, where the file is already on disk.

**Files:**
- Create: `db/migrate/20260813120000_add_original_fingerprint_to_images.rb`
- Modify: `db/structure.sql` (regenerated by the migration — commit the diff, do not hand-edit)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`ATTRIBUTES`, `create_image`)
- Modify: `app/jobs/image_crawler/pipeline/find.rb` (`download_image`)
- Test: `test/jobs/image_crawler/pipeline/find_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `images.original_fingerprint` — nullable `uuid`. Null for the URL-keyed entry presets, which have no use for it.
  - `ImageCrawler::Image#original_fingerprint` — MD5 hex of the downloaded original, set by `Pipeline::Find` and carried through the job payload.
  - `create_image` writes it to the row.

- [ ] **Step 1: Write the failing test**

Append to `test/jobs/image_crawler/pipeline/find_test.rb` (inside `class FindTest`):

```ruby
      def test_should_fingerprint_the_original_bytes
        original_url = "http://example.com/image.jpg"
        stub_request_file("image.jpeg", original_url, headers: {content_type: "image/jpeg"})

        image = Image.new_with_attributes(id: SecureRandom.hex, preset_name: "primary", image_urls: [original_url], provider: ::Image.providers[:entry_preview], provider_id: 2, feed_id: 9)
        Find.new.perform(image.to_h)

        queued = Image.new(Process.jobs.last["args"][0])
        assert_equal Digest::MD5.file(support_file("image.jpeg")).hexdigest, queued.original_fingerprint
      end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/find_test.rb -n test_should_fingerprint_the_original_bytes
```

Expected: FAIL — `queued.original_fingerprint` is `nil` (`NoMethodError` on the accessor, since it is not in `ATTRIBUTES`).

- [ ] **Step 3: Add the column**

Create `db/migrate/20260813120000_add_original_fingerprint_to_images.rb`:

```ruby
class AddOriginalFingerprintToImages < ActiveRecord::Migration[8.1]
  def change
    add_column :images, :original_fingerprint, :uuid
  end
end
```

Nullable on purpose: the entry presets are keyed by URL and never *read* it, and a row attached by `Dedupe` never gets one at all. `uuid` because MD5 is 128 bits — the same choice already load-bearing for `image_fingerprint`.

```bash
source ~/.bash_profile && bin/rails db:migrate
```

- [ ] **Step 4: Carry it through the pipeline**

In `app/jobs/image_crawler/lib/image.rb`, add `original_fingerprint` to `ATTRIBUTES` (keep the list alphabetical — it goes after `original_extension`), and add one line to `create_image`'s `attach!` call, after `image_fingerprint`:

```ruby
            original_fingerprint: original_fingerprint,
```

In `app/jobs/image_crawler/pipeline/find.rb`, in `download_image`, add the fingerprint after the four existing assignments:

```ruby
          @image.download_path      = download.persist!
          @image.final_url          = download.image_url
          @image.original_url       = original_url
          @image.original_extension = download.file_extension
          # Digest::MD5.file streams the file through the digest in C; the
          # File.read form would allocate the whole image as a Ruby string.
          @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline test/jobs/image_crawler/image_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260813120000_add_original_fingerprint_to_images.rb db/structure.sql app/jobs/image_crawler/lib/image.rb app/jobs/image_crawler/pipeline/find.rb test/jobs/image_crawler/pipeline/find_test.rb && git commit -m "Fingerprint the original bytes in the pipeline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Content-addressed storage paths

For the icon family the stored object's identity is the bytes, not the URL: `MD5("<variant>|<original_fingerprint>").<ext>`. Hashing the *original* rather than the processed output is what lets the refresh path skip processing, which for a 32×32 favicon render is the expensive part.

**Files:**
- Modify: `app/models/image.rb`
- Modify: `app/jobs/image_crawler/lib/image.rb`
- Test: `test/models/image_test.rb`, `test/jobs/image_crawler/image_test.rb`

**Interfaces:**
- Consumes: `Image.path_for` (Task 1), `original_fingerprint` (Task 5), the icon presets (Task 4).
- Produces:
  - `Image.content_storage_path_for(original_fingerprint, variant, extension) -> String`.
  - `ImageCrawler::Image#content_addressed? -> Boolean` (`preset.content_addressed == true`).
  - `ImageCrawler::Image#legacy_store? -> Boolean` (`preset.legacy_store != false`).
  - `ImageCrawler::Image#storage_path` branches on `content_addressed?`.
  - `ImageCrawler::Image#r2_source_path -> String` — `webp_path || processed_path`.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/image_test.rb`:

```ruby
  test "content_storage_path_for keys on the bytes, not the url" do
    fingerprint = Digest::MD5.hexdigest("some original bytes")
    expected = Digest::MD5.hexdigest("32x32|#{fingerprint}")

    assert_equal File.join(expected[0..2], "#{expected}.png"),
      Image.content_storage_path_for(fingerprint, "32x32", "png")

    refute_equal Image.content_storage_path_for(fingerprint, "32x32", "png"),
      Image.content_storage_path_for(fingerprint, "200x200", "png")
  end
```

Append to `test/jobs/image_crawler/image_test.rb`:

```ruby
    # Icons mutate under a stable URL, so the URL cannot name the object. Two
    # different sources that happen to serve identical bytes get one object;
    # one URL serving new bytes gets a new one.
    test "icon presets derive storage_path from the original bytes" do
      fingerprint = Digest::MD5.hexdigest("bytes")
      build = ->(url) {
        Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
          provider: ::Image.providers[:feed_icon], provider_id: 1,
          original_url: url, original_fingerprint: fingerprint
        )
      }

      assert build.call("http://a.example.com/favicon.ico").content_addressed?
      assert_equal ::Image.content_storage_path_for(fingerprint, "32x32", "png"),
        build.call("http://a.example.com/favicon.ico").storage_path
      assert_equal build.call("http://a.example.com/favicon.ico").storage_path,
        build.call("http://b.example.com/favicon.ico").storage_path
      assert_not build.call("http://a.example.com/favicon.ico").legacy_store?
    end

    test "entry presets stay keyed by url" do
      image = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "primary", image_urls: [],
        provider: ::Image.providers[:entry_preview], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: Digest::MD5.hexdigest("bytes")
      )

      assert_not image.content_addressed?
      assert image.legacy_store?
      assert_equal ::Image.storage_path_for("http://example.com/a.jpg", "542x304", "webp"), image.storage_path
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: FAIL — `undefined method 'content_storage_path_for'` and `undefined method 'content_addressed?'`.

- [ ] **Step 3: Add the model method**

In `app/models/image.rb`, add below `storage_path_for`:

```ruby
  # The icon family's stored-object identity, in contrast to storage_path_for's:
  # these sources mutate under a stable URL (/favicon.ico serves new bytes; a
  # channel changes its avatar), so the URL answers "have we seen this source?"
  # and only the bytes answer "which object is this?".
  def self.content_storage_path_for(original_fingerprint, variant, extension)
    path_for(Digest::MD5.hexdigest("#{variant}|#{original_fingerprint}"), extension)
  end
```

- [ ] **Step 4: Branch the crawler-side image**

In `app/jobs/image_crawler/lib/image.rb`, replace `storage_path` and add the predicates next to `unified?`:

```ruby
    def storage_path
      if content_addressed?
        ::Image.content_storage_path_for(original_fingerprint, variant, preset.format)
      else
        ::Image.storage_path_for(original_url, variant, preset.format)
      end
    end

    # The icon family: storage identity comes from the original bytes rather
    # than the URL, and the pipeline always downloads before deciding anything.
    def content_addressed?
      preset.content_addressed == true
    end

    # Entry presets dual-store: the legacy S3 jpg is what pre-R2 clients read.
    # Icons store one object. Presets that say nothing keep dual-storing.
    def legacy_store?
      preset.legacy_store != false
    end

    # The R2 object is the webp for the dual-format entry presets and the
    # single PNG for icons.
    def r2_source_path
      webp_path || processed_path
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/models/image.rb app/jobs/image_crawler/lib/image.rb test/models/image_test.rb test/jobs/image_crawler/image_test.rb && git commit -m "Key icon storage paths on the original bytes

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Refcount by `storage_path`

Once storage identity is content-derived, the object is the shared resource and the URL is not a proxy for it. Move garbage collection and the advisory locks onto `storage_path`. This is strictly more correct for the entry presets too: two URLs serving identical bytes currently store two objects and refcount separately.

**Files:**
- Create: `db/migrate/20260813120500_add_storage_path_index_to_images.rb`
- Modify: `db/structure.sql` (regenerated)
- Modify: `app/models/image.rb` (`with_url_lock`/`with_url_locks` → `with_storage_lock`/`with_storage_locks`)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`create_image`)
- Modify: `app/jobs/image_crawler/lib/dedupe.rb`
- Modify: `app/jobs/image_garbage_collector.rb`
- Test: `test/models/image_test.rb`, `test/jobs/image_garbage_collector_test.rb`

**Interfaces:**
- Consumes: `storage_path` from Task 6.
- Produces:
  - `Image.with_storage_lock(storage_path) { }` / `Image.with_storage_locks(paths) { }` — replace `with_url_lock`/`with_url_locks`, which are **deleted**. Same sorted single-acquisition semantics.
  - `ImageGarbageCollector#orphaned_paths(paths) -> Array<String>` — the paths from `paths` that no row references any more, across every provider.
  - Index `index_images_on_storage_path`.

- [ ] **Step 1: Write the failing tests**

In `test/models/image_test.rb`, replace the two lock tests at the bottom with:

```ruby
  test "with_storage_lock yields inside a transaction" do
    yielded = false
    Image.with_storage_lock("9e1/9e107d9d372bb6826bd81d3542a419d6.webp") do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end

  test "with_storage_locks takes many locks in one acquisition" do
    yielded = false
    paths = [
      "9e1/9e107d9d372bb6826bd81d3542a419d6.webp",
      "abc/abcdef00000000000000000000000000.png",
      "abc/abcdef00000000000000000000000000.png"
    ]
    Image.with_storage_locks(paths) do
      yielded = true
      assert Image.connection.transaction_open?
    end
    assert yielded
  end
```

Append to `test/jobs/image_garbage_collector_test.rb`:

```ruby
  # Two URLs serving identical bytes are one stored object. Refcounting by url
  # would delete it while the other row still points at it.
  test "keeps an object shared by two different urls until the last row goes" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      shared_path = Image.storage_path_for(@url, "542x304")
      one = seed_row(provider_id: 1)
      Image.create!(
        provider: :entry_preview, provider_id: "2", feed_id: 9,
        url: "http://example.com/a-different-url.jpg",
        variant: "542x304", image_fingerprint: one.image_fingerprint,
        storage_path: shared_path,
        width: 542, height: 304, bytesize: 12_345, placeholder_color: "aabbcc"
      )
      batch = stub_batch_delete

      ImageGarbageCollector.new.perform([1])
      assert_not_requested batch

      ImageGarbageCollector.new.perform([2])
      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(shared_path)
      end
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_garbage_collector_test.rb
```

Expected: FAIL — `undefined method 'with_storage_lock'`, and the shared-object test deletes the object on the first pass because the two rows have different `url_fingerprint`s.

- [ ] **Step 3: Index the column**

Create `db/migrate/20260813120500_add_storage_path_index_to_images.rb`:

```ruby
class AddStoragePathIndexToImages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :images, :storage_path, algorithm: :concurrently
  end
end
```

Garbage collection's survivor check is `WHERE storage_path IN (...)` on every run; without this it is a sequential scan.

```bash
source ~/.bash_profile && bin/rails db:migrate
```

- [ ] **Step 4: Move the locks**

In `app/models/image.rb`, replace `with_url_lock` and `with_url_locks` (keeping the surrounding comments' intent, updated for the new key):

```ruby
  # Serializes attach vs. garbage collection for one stored object. The object
  # is the shared resource -- one path can be referenced by rows from several
  # providers and several URLs -- so the path is the lock key.
  def self.with_storage_lock(storage_path, &block)
    with_storage_locks([storage_path], &block)
  end

  # Takes every lock in one sorted acquisition so concurrent multi-lock
  # holders (garbage collection batches) cannot deadlock each other.
  # `execute`, not `select_all`: pg_advisory_xact_lock returns void, a type
  # ActiveRecord's result decoder warns about (unknown OID 2278); the raw
  # result is discarded either way.
  def self.with_storage_locks(storage_paths)
    keys = storage_paths.map(&:to_s).uniq.sort
    transaction do
      connection.execute(sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtextextended(key, 0)) FROM unnest(ARRAY[?]) AS key", keys]))
      yield
    end
  end
```

Also update the comment above `attach!` — it says "every call site runs inside `Image.with_url_lock`'s transaction"; change that name to `Image.with_storage_lock`.

- [ ] **Step 5: Move the three call sites**

In `app/jobs/image_crawler/lib/image.rb`, `create_image`:

```ruby
      ::Image.with_storage_lock(storage_path) do
```

In `app/jobs/image_crawler/lib/dedupe.rb`, replace the lock and the survivor check inside `attach` (the lookup at line 18 stays on `url_fingerprint` — that is dedup's question, "have we seen this source URL?"):

```ruby
      ::Image.with_storage_lock(record.storage_path) do
        # If GC removed the last reference (and the stored objects) between
        # our lookup and here, we must not reference deleted objects. Any
        # provider's row counts: the object, not the URL, is what survives.
        if ::Image.where(storage_path: record.storage_path).exists?
```

Update the class comment's last sentence, which names the old key:

```ruby
  # The garbage collector refcounts both by storage_path, so shared
  # objects live exactly as long as their last row.
```

In `app/jobs/image_garbage_collector.rb`, rewrite `perform` and add `orphaned_paths`:

```ruby
  def perform(entry_ids)
    entry_ids = [*entry_ids].map(&:to_s)
    return if entry_ids.empty?

    rows = Image.entry_images.where(provider_id: entry_ids).to_a
    return if rows.empty?

    grouped = rows.group_by(&:storage_path)
    orphaned = []

    Image.with_storage_locks(grouped.keys) do
      Image.where(id: rows.map(&:id)).delete_all
      orphaned = orphaned_paths(grouped.keys)
      delete_r2_objects(orphaned)
    end

    legacy_urls = orphaned.flat_map { |path|
      grouped[path].filter_map { _1.data["legacy_storage_url"] }
    }.uniq
    ImageDeleter.perform_async(legacy_urls) if legacy_urls.present?

    Librato.increment("image.gc_rows", by: rows.size)
  end

  # Every provider counts, not just the entry ones: a stored object can be
  # referenced by an icon row and an entry row at once, and deleting it out
  # from under either is the same bug.
  def orphaned_paths(paths)
    paths - Image.where(storage_path: paths).distinct.pluck(:storage_path)
  end
```

Update the class comment's second paragraph, which says the locks "serialize the zero-reference check" — it is still true, just keyed on the path now; change "The advisory locks" sentence to name `storage_path`.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_garbage_collector_test.rb test/jobs/image_crawler test/jobs/entry_deleter_test.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260813120500_add_storage_path_index_to_images.rb db/structure.sql app/models/image.rb app/jobs/image_crawler/lib/image.rb app/jobs/image_crawler/lib/dedupe.rb app/jobs/image_garbage_collector.rb test/models/image_test.rb test/jobs/image_garbage_collector_test.rb && git commit -m "Refcount stored images by storage_path

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Replacement garbage collection

When new bytes change a row's `storage_path`, the object it used to point at loses a reference. Entry previews never hit this (entries do not re-crawl); every icon tenant will.

**Files:**
- Create: `app/jobs/image_replacement_collector.rb`
- Modify: `app/jobs/image_garbage_collector.rb` (extract `sweep`)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`create_image`)
- Test: `test/jobs/image_replacement_collector_test.rb` (new file), `test/jobs/image_crawler/image_test.rb`

**Interfaces:**
- Consumes: `Image.with_storage_locks`, `ImageGarbageCollector#orphaned_paths`, `#delete_r2_objects` (Task 7).
- Produces:
  - `ImageGarbageCollector#sweep(paths) -> Array<String>` — takes the locks, finds orphans, deletes their R2 objects, returns the orphaned paths.
  - `ImageReplacementCollector.perform_async(paths)`.
  - `ImageCrawler::Image#create_image` enqueues it when the row's `storage_path` changed.

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/image_replacement_collector_test.rb`:

```ruby
require "test_helper"

class ImageReplacementCollectorTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  def stub_batch_delete
    stub_request(:post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete")
      .to_return(status: 200, body: "<DeleteResult/>", headers: {content_type: "application/xml"})
  end

  def seed_row(storage_path)
    Image.create!(
      provider: :feed_icon, provider_id: SecureRandom.hex, feed_id: 9,
      url: "http://example.com/favicon.ico", variant: "32x32",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: storage_path,
      width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
    )
  end

  test "deletes an object nothing references any more" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      stub_batch_delete
      orphan = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")

      ImageReplacementCollector.new.perform([orphan])

      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(orphan)
      end
    end
  end

  # Two hosts can serve byte-identical icons. Replacing one host's icon must
  # not delete the object the other host is still pointing at.
  test "keeps an object another row still references" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      batch = stub_batch_delete
      shared = Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png")
      seed_row(shared)

      ImageReplacementCollector.new.perform([shared])

      assert_not_requested batch
    end
  end

  test "does nothing with no paths" do
    assert_nothing_raised do
      ImageReplacementCollector.new.perform([])
    end
  end
end
```

Append to `test/jobs/image_crawler/image_test.rb`:

```ruby
    test "create_image sweeps the object it replaced, and only when it changed" do
      with_env("R2_BUCKET_IMAGES" => "images-test") do
        build = ->(fingerprint) {
          Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 7,
            original_url: "http://example.com/favicon.ico",
            original_fingerprint: fingerprint,
            fingerprint: SecureRandom.hex(16),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
          )
        }

        first = build.call(Digest::MD5.hexdigest("old bytes"))
        assert_no_difference -> { ImageReplacementCollector.jobs.size } do
          first.create_image
        end

        assert_no_difference -> { ImageReplacementCollector.jobs.size } do
          build.call(Digest::MD5.hexdigest("old bytes")).create_image
        end

        assert_difference -> { ImageReplacementCollector.jobs.size }, +1 do
          build.call(Digest::MD5.hexdigest("new bytes")).create_image
        end

        assert_equal [[first.storage_path]], ImageReplacementCollector.jobs.last["args"]
      end
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_replacement_collector_test.rb test/jobs/image_crawler/image_test.rb
```

Expected: FAIL with `uninitialized constant ImageReplacementCollector`.

- [ ] **Step 3: Extract the sweep**

In `app/jobs/image_garbage_collector.rb`, add `sweep` and call it from `perform`. `perform` still deletes its rows inside the same lock, so it cannot simply delegate — it acquires the locks itself and calls the shared orphan check:

```ruby
  # The locked half of collection, on its own so the replacement path can use
  # it without having rows to delete first.
  def sweep(paths)
    paths = Array(paths).compact.uniq
    return [] if paths.empty?

    orphaned = []
    Image.with_storage_locks(paths) do
      orphaned = orphaned_paths(paths)
      delete_r2_objects(orphaned)
    end
    orphaned
  end
```

Create `app/jobs/image_replacement_collector.rb`:

```ruby
# The other half of image garbage collection. ImageGarbageCollector starts
# from rows that are going away (an entry was deleted); this starts from a
# stored object a row has already stopped pointing at, because its source
# served new bytes. Both end in the same locked survivor check and the same
# batched delete -- only the starting set differs.
#
# Unreachable for entry previews (entries never re-crawl), routine for every
# icon tenant: /favicon.ico serving new bytes is the whole problem the icon
# family exists to solve.
class ImageReplacementCollector
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(storage_paths)
    ImageGarbageCollector.new.sweep([*storage_paths])
  end
end
```

- [ ] **Step 4: Enqueue it on replacement**

In `app/jobs/image_crawler/lib/image.rb`, replace `create_image`:

```ruby
    def create_image
      record = ::Image.with_storage_lock(storage_path) do
        ::Image.attach!(
          provider: provider,
          provider_id: provider_id,
          feed_id: feed_id,
          url: original_url,
          variant: variant,
          image_fingerprint: fingerprint,
          original_fingerprint: original_fingerprint,
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

      # The row moved to a different object, so the old one may now be
      # unreferenced. Swept in its own job because it is a different lock key
      # than the one held above, and taking both here would invert the sorted
      # acquisition order that keeps GC batches from deadlocking.
      if record.saved_change_to_storage_path? && (replaced = record.storage_path_before_last_save)
        ImageReplacementCollector.perform_async([replaced])
      end

      record
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_replacement_collector_test.rb test/jobs/image_crawler test/jobs/image_garbage_collector_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_replacement_collector.rb app/jobs/image_garbage_collector.rb app/jobs/image_crawler/lib/image.rb test/jobs/image_replacement_collector_test.rb test/jobs/image_crawler/image_test.rb && git commit -m "Collect the stored object an image row replaced

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: `Pipeline::Find` branches on the preset

The icon family must not use `Dedupe`. Skipping the download because a row already exists for that URL is correct for previews — an og:image URL's content is fixed and the entry never re-crawls — and exactly wrong for icons. Icons always fetch, then short-circuit *after* the download on an `original_fingerprint` match: no processing, no upload, no row write, and above all no `touch`.

**Files:**
- Modify: `app/jobs/image_crawler/pipeline/find.rb`
- Modify: `app/jobs/image_crawler/pipeline/process.rb`
- Modify: `app/jobs/image_crawler/pipeline/upload.rb`
- Test: `test/jobs/image_crawler/pipeline/find_test.rb`, `test/jobs/image_crawler/pipeline/upload_test.rb`

**Interfaces:**
- Consumes: `content_addressed?`, `legacy_store?`, `r2_source_path` (Task 6); `original_fingerprint` (Task 5).
- Produces:
  - `Pipeline::Find#attempt_icon(original_url) -> Boolean` — downloads, fingerprints, and either enqueues `Process` or stops.
  - `Pipeline::Find#unchanged? -> Boolean` — true when a row for this `(provider, provider_id)` already has this `original_fingerprint`.
  - `Pipeline::Process` renders content-addressed presets with a single `crop!` instead of `crop_pair!`.
  - `Pipeline::Upload` skips the legacy S3 PUT for `legacy_store? == false`, and uploads `r2_source_path` to R2.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/pipeline/find_test.rb`:

```ruby
      # Dedupe's shortcut is skip-the-download-because-a-row-exists. For icons
      # the row proves nothing about the bytes behind the URL, so the fetch
      # always happens and the short circuit is after it.
      def test_should_always_download_an_icon_even_with_a_row_for_the_url
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/favicon.ico"
          stub_request_file("favicon.ico", original_url, headers: {content_type: "image/x-icon"})

          ::Image.create!(
            provider: :feed_icon, provider_id: "5", feed_id: 9,
            url: original_url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("different bytes"),
            storage_path: ::Image.content_storage_path_for(Digest::MD5.hexdigest("different bytes"), "32x32", "png"),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc"
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [original_url],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9
          )

          assert_difference -> { Process.jobs.size }, +1 do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
        end
      end

      # An unchanged icon must cost one download and nothing else: no vips
      # work, no upload, and no row write -- the row's updated_at is a view
      # cache key, so a write here would invalidate every view referencing it
      # on every crawl.
      def test_should_stop_after_the_download_when_the_icon_is_unchanged
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/favicon.ico"
          stub_request_file("favicon.ico", original_url, headers: {content_type: "image/x-icon"})
          fingerprint = Digest::MD5.file(support_file("favicon.ico")).hexdigest

          row = ::Image.create!(
            provider: :feed_icon, provider_id: "5", feed_id: 9,
            url: original_url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: fingerprint,
            storage_path: ::Image.content_storage_path_for(fingerprint, "32x32", "png"),
            width: 32, height: 32, bytesize: 500, placeholder_color: "aabbcc",
            updated_at: 1.year.ago
          )

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [original_url],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9
          )

          assert_no_difference -> { Process.jobs.size } do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
          assert_equal 1.year.ago.to_i, row.reload.updated_at.to_i
        end
      end
```

Append to `test/jobs/image_crawler/pipeline/upload_test.rb`:

```ruby
      def test_should_store_icons_only_in_r2
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.png")
          original_url = "http://example.com/favicon.ico"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "favicon", image_urls: [],
            provider: ::Image.providers[:feed_icon], provider_id: 5, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 32, height: 32, placeholder_color: "0867e2"
          )

          legacy = stub_request(:put, /s3\.amazonaws\.com/)
          r2_put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .with(headers: {"Content-Type" => "image/png"})

          assert_difference -> { ::Image.count }, +1 do
            Upload.new.perform(image.to_h)
          end

          assert_requested r2_put
          assert_not_requested legacy

          record = ::Image.find_by(provider: ::Image.providers[:feed_icon], provider_id: "5")
          assert_equal image.storage_path, record.storage_path
          assert_equal Digest::MD5.hexdigest("bytes"), record.original_fingerprint.delete("-")
        end
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/find_test.rb test/jobs/image_crawler/pipeline/upload_test.rb
```

Expected: FAIL — `Find` routes the icon preset through `attempt_unified`, so the unchanged case still downloads *and* processes; `Upload` PUTs to S3 and raises on `webp_path` being nil.

- [ ] **Step 3: Branch `Find`**

In `app/jobs/image_crawler/pipeline/find.rb`, replace the dispatch inside the `while` loop:

```ruby
          if @image.content_addressed?
            break if attempt_icon(original_url)
          elsif @image.unified?
            break if attempt_unified(original_url)
          else
            break if attempt_legacy(original_url)
          end
```

and add `attempt_icon` and `unchanged?` after `attempt_legacy`:

```ruby
      # Icons mutate under a stable URL, so a row for this URL says nothing
      # about the bytes behind it and Dedupe's skip-the-download shortcut is
      # exactly wrong. Always fetch, then short-circuit on the original bytes:
      # hashing the original rather than the processed output is what lets this
      # skip *processing*, which for a 32x32 render is the expensive part.
      def attempt_icon(original_url)
        download = begin
          Download.download!(original_url, camo: @image.camo, minimum_size: @image.preset.minimum_size)
        rescue => exception
          Sidekiq.logger.info @image.trace(message: "download exception", metadata: {exception: exception, original_url: original_url})
          return false
        end

        return false unless download

        unless download.valid?
          download.delete!
          Sidekiq.logger.info @image.trace(message: "download invalid", metadata: {original_url: original_url})
          return false
        end

        @image.download_path        = download.persist!
        @image.final_url            = download.image_url
        @image.original_url         = original_url
        @image.original_extension   = download.file_extension
        @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest

        if unchanged?
          Librato.increment("image.icon_unchanged")
          Sidekiq.logger.info @image.trace(message: "icon unchanged", metadata: {original_url: original_url})
          begin
            File.unlink(@image.download_path)
          rescue Errno::ENOENT
          end
          return true
        end

        Process.perform_async(@image.to_h)
        Sidekiq.logger.info @image.trace(message: "download valid", metadata: {image_url: @image.final_url})
        true
      end

      def unchanged?
        ::Image
          .where(provider: @image.provider, provider_id: @image.provider_id.to_s)
          .where(original_fingerprint: @image.original_fingerprint)
          .exists?
      end
```

- [ ] **Step 4: Branch `Process` and `Upload`**

In `app/jobs/image_crawler/pipeline/process.rb`, replace the format branch inside `if processor.valid?(...)`:

```ruby
          # Dual-format is the entry presets' arrangement: one geometry pass,
          # a legacy jpg and an R2 webp. Icons store a single PNG.
          if @image.unified? && !@image.content_addressed?
            pair = processor.crop_pair!
            cropped = pair[:jpg]
            webp = pair[:webp]

            @image.webp_path   = webp.file
            @image.bytesize    = webp.size
            @image.fingerprint = webp.fingerprint
          else
            cropped = processor.crop!
            @image.bytesize    = cropped.size
            @image.fingerprint = cropped.fingerprint
          end
```

and exempt icons from the feed-scoped reuse check, which is a rule about entry previews repeating a photograph:

```ruby
      def reuse_rejected?
        return false unless @image.unified?
        return false if @image.content_addressed?
        ReuseRules.new(@image).fingerprint_used_in_feed?(@image.fingerprint)
      end
```

In `app/jobs/image_crawler/pipeline/upload.rb`, make the legacy PUT conditional and read the R2 source through the accessor:

```ruby
      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload if @image.legacy_store?
        r2_stored = false
```

```ruby
      def upload_r2
        File.open(@image.r2_source_path) do |file|
          Fog::Storage.new(STORAGE_R2).put_object(@image.r2_bucket, @image.storage_path, file, @image.r2_storage_options)
        end
      end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler
```

Expected: PASS.

- [ ] **Step 6: Run the whole suite — this is the end of Phase A**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. Read the actual output; do not infer it.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/image_crawler/pipeline test/jobs/image_crawler/pipeline && git commit -m "Branch the pipeline on content-addressed presets

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

# Phase B — View cache digest

### Task 10: `Favicon.for_entries` resolves every entry's icon host

`for_entries` currently collects hosts only for Pages entries, because that is the one case with no association to preload. The digest needs the record for *every* entry, and it needs it from a map rather than a per-row lookup: a cache key that triggers a query per row would trade 100k writes for an N+1 on every render.

**Files:**
- Modify: `app/models/favicon.rb`
- Test: `test/models/favicon_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Favicon.host_for(entry) -> String | nil` — the host an entry's favicon is keyed by: the entry's own hostname for Pages feeds, the feed's host otherwise.
  - `Favicon.for_entries(entries) -> Hash{String => Favicon}` — now covers every entry, keyed by host.

- [ ] **Step 1: Write the failing test**

Replace the contents of `test/models/favicon_test.rb` with:

```ruby
require "test_helper"

class FaviconTest < ActiveSupport::TestCase
  test "should require a url" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Favicon.create!(url: nil)
    end
  end

  # Pages entries resolve by their own hostname (one Pages feed holds entries
  # from everywhere); everything else resolves by its feed's host.
  test "host_for uses the entry's host for pages and the feed's otherwise" do
    pages_feed, xml_feed = create_feeds(users(:ben), 2)
    pages_feed.update!(feed_type: :pages)
    xml_feed.update!(host: "blog.example.com")

    pages_entry = create_entry(pages_feed)
    pages_entry.update!(url: "http://saved.example.com/article")
    xml_entry = create_entry(xml_feed)

    assert_equal "saved.example.com", Favicon.host_for(pages_entry)
    assert_equal "blog.example.com", Favicon.host_for(xml_entry)
  end

  test "for_entries resolves pages and feed hosts together in one query" do
    pages_feed, xml_feed = create_feeds(users(:ben), 2)
    pages_feed.update!(feed_type: :pages)
    xml_feed.update!(host: "blog.example.com")

    saved = Favicon.create!(host: "saved.example.com", url: "http://cdn.example.com/saved.png")
    blog = Favicon.create!(host: "blog.example.com", url: "http://cdn.example.com/blog.png")

    pages_entry = create_entry(pages_feed)
    pages_entry.update!(url: "http://saved.example.com/article")
    entries = [pages_entry, create_entry(xml_feed)]

    favicons = nil
    statements = capture_sql { favicons = Favicon.for_entries(entries) }

    assert_equal saved, favicons["saved.example.com"]
    assert_equal blog, favicons["blog.example.com"]
    assert_equal 1, statements.count { _1.match?(/FROM "favicons"/i) }
  end

  test "for_entries is empty with nothing to resolve" do
    assert_equal({}, Favicon.for_entries([]))
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/models/favicon_test.rb
```

Expected: FAIL with `undefined method 'host_for'`, and `for_entries` returning `{}` for the xml entry.

- [ ] **Step 3: Widen the lookup**

In `app/models/favicon.rb`, replace `for_entries` and add `host_for`:

```ruby
  # Which host an entry's favicon is keyed by. Pages entries are looked up by
  # the entry's own host rather than the feed's -- one Pages feed holds entries
  # from everywhere -- so there is no association to reach through.
  def self.host_for(entry)
    entry.feed&.pages? ? entry.hostname : entry.feed&.host
  end

  # Resolve the whole collection in one query. This map is both what the entry
  # list renders Pages icons from and what the view cache digest reads, so a
  # miss here is an N+1 on every render rather than a single extra query.
  def self.for_entries(entries)
    hosts = Array(entries).filter_map { host_for(_1) }.uniq
    return {} if hosts.empty?
    where(host: hosts).index_by(&:host)
  end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
source ~/.bash_profile && bin/rails test test/models/favicon_test.rb test/views test/presenters
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/favicon.rb test/models/favicon_test.rb && git commit -m "Resolve every entry's favicon host in one query

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: `entries_cache_key` digests the favicon and the preview image

`[entry, entry.feed, "v7"]` uses the feed's timestamp as a proxy for its favicon, which is why a medium.com favicon change needs 100,000 feed writes. Put the records in the digest instead: cache keys are computed at render time from loaded records, so one row update invalidates every view referencing it, at any scale.

**Files:**
- Modify: `app/helpers/entries_helper.rb`
- Modify: `app/views/shared/_entries.js.erb` (line 8)
- Test: `test/views/entries_list_test.rb` — the existing home for this key's tests; it already has a private `entry_cache_key` helper and a `favicon_queries` matcher.

**Interfaces:**
- Consumes: `Favicon.host_for` (Task 10).
- Produces: `EntriesHelper.entries_cache_key(entry, favicons = {}) -> Array` — `[entry, entry.feed, favicons[Favicon.host_for(entry)], entry.preview_image_record, "v8"]`. The instance method forwards with the same signature. The default `{}` keeps the existing one-argument call sites working.

- [ ] **Step 1: Write the failing tests**

In `test/views/entries_list_test.rb`, widen the private helper at the bottom to take the map:

```ruby
  # The lambda shared/_entries.js.erb uses to key the collection cache.
  def entry_cache_key(entry, favicons = {})
    ActiveSupport::Cache.expand_cache_key(EntriesHelper.entries_cache_key(entry, favicons))
  end
```

Replace the existing "building the cache key does not walk an association per entry" test — the preview image record is the second association the key now reaches, and it has the same N+1 exposure the favicon had:

```ruby
  test "building the cache key does not walk an association per entry" do
    ids = 5.times.map { create_entry(@feed).id }
    entries = Entry.where(id: ids).includes(:feed).preload(:preview_image_record).to_a
    favicons = Favicon.for_entries(entries)

    statements = capture_sql { entries.each { entry_cache_key(_1, favicons) } }

    assert_empty favicon_queries(statements)
    assert_empty statements.select { _1.match?(/FROM "images"/i) },
      "the key reaches preview_image_record, so it must be preloaded"
  end
```

and add two tests above the `private` marker:

```ruby
  # The favicon is its own row with its own timestamp. Digesting the record is
  # what lets one row update invalidate every view referencing it; the
  # alternative was TouchFeeds writing to every feed on the host -- 100,000
  # rows for a host like medium.com.
  test "changing the favicon changes the key without touching the feed" do
    entry = create_entry(@feed)
    entry.update!(url: "http://icons.example.com/article")
    favicon = Favicon.create!(host: "icons.example.com", url: "http://example.com/a.png")

    before = entry_cache_key(entry, Favicon.for_entries([entry]))
    feed_updated_at = @feed.reload.updated_at

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    refute_equal before, entry_cache_key(entry, Favicon.for_entries([entry]))
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  test "storing a preview image changes the key" do
    entry = create_entry(@feed)
    before = entry_cache_key(entry)

    Image.create!(
      provider: :entry_preview, provider_id: entry.id.to_s, feed_id: @feed.id,
      url: "http://example.com/a.jpg", variant: "542x304",
      image_fingerprint: SecureRandom.hex(16),
      storage_path: Image.storage_path_for("http://example.com/a.jpg", "542x304"),
      width: 542, height: 304, bytesize: 1, placeholder_color: "aabbcc"
    )

    refute_equal before, entry_cache_key(Entry.find(entry.id))
  end
```

(`Entry.find` rather than `entry` in the last line: the `has_one` memoized `nil` on the object that existed before the row did.)

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/views/entries_list_test.rb
```

Expected: FAIL on both new tests — the key is unchanged, because neither record is in it. The N+1 test still passes at this point; it is a guard for the change you are about to make.

- [ ] **Step 3: Put the records in the digest**

In `app/helpers/entries_helper.rb`, replace both `entries_cache_key` definitions:

```ruby
  # The entry summary renders the feed's title as well as its icon and
  # favicon, so key on the feed record rather than enumerating the attributes
  # the partial happens to use today.
  #
  # The favicon and the preview image are separate rows with their own
  # timestamps, and both render into this partial. Digesting the records is
  # what lets one row update invalidate every view referencing it: the
  # alternative is touching every owner row, which is what TouchFeeds did for
  # a favicon change -- 100,000 writes to invalidate views on a host like
  # medium.com.
  #
  # Both must come from something already loaded. favicons is the
  # collection-wide map (Favicon.for_entries); preview_image_record comes from
  # Entry.entries_list's preload. A lookup here would be an N+1 per render.
  def self.entries_cache_key(entry, favicons = {})
    [entry, entry.feed, favicons[Favicon.host_for(entry)], entry.preview_image_record, "v8"]
  end

  def entries_cache_key(entry, favicons = {})
    EntriesHelper.entries_cache_key(entry, favicons)
  end
```

- [ ] **Step 4: Pass the map from the entry list**

In `app/views/shared/_entries.js.erb`, line 8, pass the already-built map into the lambda:

```erb
        var entries = "<%= j render partial: "entries/entry", collection: @entries, locals: {favicons: favicons}, cached: -> (entry) { entries_cache_key(entry, favicons) } %>";
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/views/entries_list_test.rb test/views/query_count_test.rb
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/entries_helper.rb app/views/shared/_entries.js.erb test/views/entries_list_test.rb && git commit -m "Digest the favicon and preview image rows in the entry cache key

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: `CacheEntryViews` warms the same keys the live render reads

`CacheEntryViews` renders with `cached: true`, which uses the bare entry key. After Task 11 the warm cache and the live render would disagree about keys, so the warming would write entries nobody ever reads.

**Files:**
- Modify: `app/jobs/cache_entry_views.rb`
- Test: `test/jobs/cache_entry_views_test.rb`

**Interfaces:**
- Consumes: `EntriesHelper.entries_cache_key` (Task 11), `Favicon.for_entries` (Task 10).
- Produces: nothing new. `cache_views` renders with the same lambda, the same `favicons` local, and preloads `preview_image_record`.

- [ ] **Step 1: Write the failing test**

`config.action_controller.perform_caching` is **false** in the test environment, so nothing this job renders reaches the cache store and an "is the fragment there?" assertion would pass vacuously forever. Assert on the key the job *asks for* instead — that is the thing that silently breaks.

Append to `test/jobs/cache_entry_views_test.rb`:

```ruby
  # Fragment caching is off in the test environment, so this is about the key
  # the job asks for, not about what lands in the store. A bare `cached: true`
  # here warms a key the entry list never looks up: the warm pass and the live
  # render would disagree, and every view would render cold anyway.
  test "warms the key the entry list will look up" do
    Favicon.create!(host: @entry.feed.host, url: "http://example.com/a.png")
    CacheEntryViews.new.perform(@entry.id)

    captured = nil
    original = ApplicationController.method(:render)
    capture = ->(options = {}, *rest, &block) {
      captured = options if options.is_a?(Hash) && options[:partial] == "entries/entry"
      original.call(options, *rest, &block)
    }

    ApplicationController.stub(:render, capture) do
      CacheEntryViews.new.perform(nil, true)
    end

    assert_not_nil captured, "the job should render the entry partial as a collection"

    entry = captured[:collection].first
    favicons = captured[:locals][:favicons]

    assert_equal Favicon.for_entries([entry]), favicons
    assert_respond_to captured[:cached], :call
    assert_equal EntriesHelper.entries_cache_key(entry, favicons), captured[:cached].call(entry)
  end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/jobs/cache_entry_views_test.rb
```

Expected: FAIL — `captured[:cached]` is `true`, which does not respond to `call`, and there is no `:locals` key at all.

- [ ] **Step 3: Render with the shared key**

In `app/jobs/cache_entry_views.rb`, replace `cache_views`:

```ruby
  def cache_views
    entry_ids = dequeue_ids(SET_NAME)
    entries = Entry.where(id: entry_ids).includes(feed: [:favicon]).preload(:preview_image_record).to_a
    favicons = Favicon.for_entries(entries)

    # The same lambda and the same locals the entry list renders with. A bare
    # `cached: true` here would warm a key nothing ever looks up.
    ApplicationController.render({
      partial: "entries/entry",
      collection: entries,
      format: :html,
      locals: {favicons: favicons},
      cached: ->(entry) { EntriesHelper.entries_cache_key(entry, favicons) }
    })
    ApplicationController.render({
      layout: nil,
      template: "api/v2/entries/index",
      assigns: {entries: entries},
      format: :html,
      locals: {
        params: {mode: "extended"}
      }
    })
  end
```

The API template's own `cached:` proc stays keyed on the entry alone — that view renders no favicon, and `EntryImage#receive`'s `@entry.touch` is what invalidates it.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/cache_entry_views_test.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/cache_entry_views.rb test/jobs/cache_entry_views_test.rb && git commit -m "Warm entry views under the key the entry list reads

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: The sidebar cache key gains its feeds' favicons

The sidebar renders `FaviconComponent` for every feed, in two separately-cached sections. Both keys use the feed record as a proxy for its favicon, which only worked because `TouchFeeds` wrote to the feed. Both `@feeds` and `tag_group`'s feeds are already `includes(:favicon)`, so this costs no query.

The keys are inline literals in ERB, and fragment caching is off in the test environment, so there is nothing to assert against as written. Move them into a helper — the same shape `EntriesHelper.entries_cache_key` already has — and test the helper.

**Files:**
- Create: `app/helpers/feeds_helper.rb`
- Create: `test/helpers/feeds_helper_test.rb`
- Modify: `app/views/feeds/_feeds.html.erb` (lines 28 and 37)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `FeedsHelper.sidebar_feeds_cache_key(feeds) -> Array` — `[feeds, feeds.map(&:title), feeds.map(&:favicon), "v4"]`.
  - `FeedsHelper.sidebar_tags_cache_key(tags) -> Array` — `[tags, tags.map(&:user_feeds), <titles>, <favicons>, "v10"]`.
  - Instance methods of the same names forwarding to the module methods, so the ERB can call them bare (Rails includes all helpers in views by default).

- [ ] **Step 1: Write the failing test**

Create `test/helpers/feeds_helper_test.rb`:

```ruby
require "test_helper"

class FeedsHelperTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @feed = create_feeds(@user).first
  end

  def loaded_feeds
    @user.feeds.where(id: @feed.id).includes(:favicon).to_a
  end

  # The sidebar renders a FaviconComponent per feed, and a favicon is its own
  # row with its own timestamp. The key used the feed record as a proxy for it,
  # which only worked because TouchFeeds wrote to the feed.
  test "the feeds key changes when a favicon changes, without touching the feed" do
    favicon = Favicon.create!(host: @feed.host, url: "http://example.com/a.png")

    before = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_feeds_cache_key(loaded_feeds))
    feed_updated_at = @feed.reload.updated_at

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    after = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_feeds_cache_key(loaded_feeds))

    refute_equal before, after
    assert_equal feed_updated_at.to_i, @feed.reload.updated_at.to_i
  end

  test "the tags key changes when a tagged feed's favicon changes" do
    @feed.tag("News", @user)
    favicon = Favicon.create!(host: @feed.host, url: "http://example.com/a.png")

    before = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_tags_cache_key(@user.tag_group))

    travel 1.minute do
      favicon.update!(url: "http://example.com/b.png")
    end

    after = ActiveSupport::Cache.expand_cache_key(FeedsHelper.sidebar_tags_cache_key(@user.tag_group))

    refute_equal before, after
  end

  # Both @feeds and tag_group's feeds are already includes(:favicon), so this
  # costs nothing -- but only as long as the key reads what was preloaded.
  test "the feeds key does not query favicons when they are preloaded" do
    Favicon.create!(host: @feed.host, url: "http://example.com/a.png")
    feeds = loaded_feeds

    statements = capture_sql { FeedsHelper.sidebar_feeds_cache_key(feeds) }

    assert_empty statements.select { _1.match?(/FROM "favicons"/i) }
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/helpers/feeds_helper_test.rb
```

Expected: FAIL with `uninitialized constant FeedsHelper`.

- [ ] **Step 3: Create the helper**

Create `app/helpers/feeds_helper.rb`:

```ruby
module FeedsHelper
  # The sidebar renders a FaviconComponent per feed, and a favicon is its own
  # row with its own timestamp -- nothing writes to the feed when one changes.
  # Digesting the records is what invalidates these fragments now that the
  # TouchFeeds fan-out is gone. Both collections reach here already
  # includes(:favicon), so it costs no query.
  def self.sidebar_feeds_cache_key(feeds)
    [feeds, feeds.map(&:title), feeds.map(&:favicon), "v4"]
  end

  # titles come from subscriptions, so a rename does not touch the feed's key
  def self.sidebar_tags_cache_key(tags)
    feeds = tags.flat_map(&:user_feeds)
    [tags, tags.map(&:user_feeds), feeds.map(&:title), feeds.map(&:favicon), "v10"]
  end

  def sidebar_feeds_cache_key(feeds)
    FeedsHelper.sidebar_feeds_cache_key(feeds)
  end

  def sidebar_tags_cache_key(tags)
    FeedsHelper.sidebar_tags_cache_key(tags)
  end
end
```

- [ ] **Step 4: Call it from the sidebar**

In `app/views/feeds/_feeds.html.erb`, replace line 28 (and the comment above it, which now lives in the helper):

```erb
  <% cache sidebar_tags_cache_key(tags) do %>
```

and line 37:

```erb
  <% cache sidebar_feeds_cache_key(feeds) do %>
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/helpers/feeds_helper_test.rb test/controllers
```

Expected: PASS. The controller run is what proves the ERB still renders — a missing helper method there is a 500, not a cache miss.

- [ ] **Step 6: Commit**

```bash
git add app/helpers/feeds_helper.rb app/views/feeds/_feeds.html.erb test/helpers/feeds_helper_test.rb && git commit -m "Digest feed favicons in the sidebar cache keys

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14: Delete `Favicon#touch_owners` and `TouchFeeds`

Every view that renders a favicon now has that row in its cache key, so the fan-out has no remaining job. This is the payoff: a medium.com favicon change goes from 100,000 feed writes to one row update.

**Files:**
- Modify: `app/models/favicon.rb` (remove `after_commit :touch_owners` and the method)
- Delete: `app/jobs/touch_feeds.rb`
- Delete: `test/jobs/touch_feeds_test.rb`
- Test: `test/models/favicon_test.rb`

**Interfaces:**
- Consumes: Tasks 11–13.
- Produces: `TouchFeeds` no longer exists.

- [ ] **Step 1: Confirm nothing else references it**

```bash
source ~/.bash_profile && rg -n "TouchFeeds|touch_owners" --hidden --glob '!.git'
```

Expected: hits only in `app/models/favicon.rb`, `app/jobs/touch_feeds.rb`, and `test/jobs/touch_feeds_test.rb`. If anything else appears — a scheduler entry, a Sidekiq queue config, a cron — stop and report it rather than deleting.

- [ ] **Step 2: Write the failing test**

Append to `test/models/favicon_test.rb`:

```ruby
  # The fan-out is gone: the favicon row is in the view cache digest, so
  # invalidation is the row's own updated_at and nothing needs to write to the
  # feeds that reference it. Asserted through the queue rather than
  # `defined?(TouchFeeds)`, which is nil in a non-eager-loading environment
  # whether the class exists or not.
  test "changing a favicon's url enqueues no fan-out" do
    Feed.create!(feed_url: "http://fanout.example.com/feed", host: "fanout.example.com", title: "F")
    favicon = Favicon.create!(host: "fanout.example.com", url: "http://cdn.example.com/a.png")
    flush_redis

    favicon.update!(url: "http://cdn.example.com/b.png")

    assert_empty Sidekiq::Worker.jobs
  end
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
source ~/.bash_profile && bin/rails test test/models/favicon_test.rb
```

Expected: FAIL — one `TouchFeeds` job is queued by the `after_commit`.

- [ ] **Step 4: Delete the fan-out**

In `app/models/favicon.rb`, remove these three lines:

```ruby
  after_commit :touch_owners

  def touch_owners
    TouchFeeds.perform_in(rand(1..10).seconds, host) if saved_change_to_attribute?(:url)
  end
```

Then:

```bash
source ~/.bash_profile && git rm app/jobs/touch_feeds.rb test/jobs/touch_feeds_test.rb
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
source ~/.bash_profile && bin/rails test test/models/favicon_test.rb
```

Expected: PASS.

- [ ] **Step 6: Run the whole suite — this is the end of Phase B**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. Read the actual output. If it looks hung with no output, that is the RTK output compression, not a hang — the real failure detail is in the RTK tee log.

- [ ] **Step 7: Commit**

```bash
git add -A app/models/favicon.rb app/jobs/touch_feeds.rb test/jobs/touch_feeds_test.rb test/models/favicon_test.rb && git commit -m "Delete the favicon touch fan-out

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Manual verification before merge

The suite covers the mechanics; these two need eyes.

- [ ] **Icon rendering, by hand.** In `bin/rails console`, run a real favicon through the new preset and look at the output — nothing displays these yet, so a wrong render produces no visual signal and no complaint:

```ruby
path = ImageCrawler::Processor::Cropper.new(
  Rails.root.join("test/support/www/favicon.ico").to_s,
  crop: :icon_crop, extension: "ico", width: 200, height: 200
).crop!.file
`open #{path}`
```

Confirm it is a PNG, not upscaled past the source's own dimensions, and not a blank or white square.

- [ ] **Cache invalidation, in the browser.** Sign in at `https://feedbin.resolv.app/auto_sign_in`, note a feed's icon, then update that `Favicon` row's `url` in the console and reload. The icon must change without any write to `feeds`, and the sidebar must change too. (Touch `tmp/restart.txt` first if initializers look stale after a branch switch.)

## What this plan deliberately leaves out

Recorded so the next plan's author does not have to re-derive them:

- **No tenant moves.** Favicons, apple touch icons, podcast show/episode art, and YouTube channel avatars all still write where they write today. The icon presets have `job_class: nil` and no scheduler.
- **`legacy_store: false` is set only on the icon presets.** Phase C's podcast icons will likely need `legacy_store: true` while `entries.media_image` is still the read model — that is a preset flag, not a code change.
- **The `entry_icon` provider is still outside `Image.entry_images`,** so `ImageGarbageCollector#perform` does not collect episode art on entry deletion. Fixing that leak is Phase C's, and it is a one-line scope change plus a test.
- **Conditional HTTP stays disabled** in `FaviconCrawler::Finder`. Re-enabling it is Phase E's, once rows own their own `Etag`/`Last-Modified` per URL.
- **`Etag`/`Last-Modified` have no home yet.** They go in `images.data` per row, in Phase E.
