# Icon Family Phase C — Podcast Artwork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move podcast show artwork and episode artwork onto the `images` table and R2, keyed by the fingerprint of the original bytes, so one stored object serves a show and all of its episodes instead of one object per episode — and so deleting an entry actually collects its artwork.

**Architecture:** The `podcast` and `podcast_feed` presets become `unified` (they write an `images` row and an R2 object) and `content_addressed` (their `storage_path` derives from the original bytes rather than the URL, and `Pipeline::Find` always downloads then short-circuits on an unchanged fingerprint). They keep `legacy_store: true` throughout, so the existing S3 object and the existing `entries.media_image` / `feeds.custom_icon` values continue to be written — the read paths prefer the row and fall back to those, exactly as entry previews did during their own transition. Two pieces of foundation land first: closing the upload-before-lock window that Phase A left open, and widening garbage collection's harvest to cover entry-owned icon rows.

**Tech Stack:** Rails 8.1, Sidekiq, Fog::Storage (AWS provider; R2 is S3-compatible), libvips via ImageProcessing::Vips, Postgres, Redis, minitest + webmock.

**Design doc:** `docs/superpowers/specs/2026-08-13-icon-family-design.md` — in particular the section "What Phases A and B learned — read before starting Phase C", which this plan's Tasks 1 and 2 exist to answer.

**Predecessor:** `docs/superpowers/plans/2026-08-13-icon-family-foundation.md` (Phases A and B, complete). Everything this plan consumes was built there.

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`. A single test: `bin/rails test <path> -n <name>`.
- NEVER interpolate values into SQL strings — use hash conditions, binds, or `sanitize_sql_array`.
- **Podcast artwork keeps its current rendering recipe: `crop: :fill_crop`, `format: "jpg"`, 200×200.** The design doc's per-tenant table says "limit, png"; that was generalized from the favicon family and is **not** followed here. Three reasons, all load-bearing: the UI renders these in a square slot and sets `custom_icon_format: "square"`, and `limit` would letterbox a non-square cover; `icon_crop`'s `IconLayer` rejects any source whose average colour is white, which would silently drop a mostly-white podcast cover; and `touch_icon` is already 200×200 **png**, so keeping podcast at jpg is what keeps the two presets' object keys distinct at the same variant.
- **Do not change behavior for any other preset.** `primary`/`twitter`/`youtube` keep 542×304 WebP + jpg. `favicon`/`touch_icon` keep 32×32 / 200×200 png. `icon` (remote_file) keeps `limit_crop`. Their existing tests must stay green **without being edited**.
- **`Image.entry_images` must not change.** It reads `%i[entry_link_preview entry_preview]`, and `Dedupe` (`dedupe.rb:18`) plus `ReuseRules` (`reuse_rules.rb:26,45`) depend on that narrow meaning — it is the reason an icon crawl can never match an entry-preview row. Task 2 adds a *separate* scope for garbage collection rather than widening this one.
- **MD5, not SHA1**, for every new fingerprint, and always `Digest::MD5.file(path).hexdigest`.
- **The touch rule still governs `images` rows.** A row's `updated_at` may change only when the stored bytes actually change.
- All pipeline jobs remain `retry: false`.
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## Two things this plan deliberately does NOT do

Both look like gaps against the design doc's stated per-tenant pattern ("flag the preset in, add the association and row-first reads, touch-only callback, retire the legacy store"). Neither is an oversight.

**No touch-only callback.** `ItunesImage#receive` keeps writing `entries.media_image` and `ItunesFeedImage#receive` keeps writing `feeds.custom_icon`. That pattern exists to kill *fan-out*: one favicon change writing to every feed on a host, 100,000 rows for medium.com. Podcast artwork has no fan-out — one show's art change writes one feed row, one episode's writes one entry row. Those writes are also what keeps the legacy fallback correct while `legacy_store` is on. They retire with the legacy store, in a later phase.

**No cache-key changes.** Because the owner rows are still written, `entries_cache_key`'s `entry` and `entry.feed` elements still change when artwork changes, and the sidebar keys' `feeds` element does too. Episode art renders in `entries/_media.html.erb` and `entries/_audio_markup.html.erb`, neither of which is inside a `cache` block at all. Adding the icon record to those keys becomes necessary only when the owner writes go away.

---

### Task 1: Close the upload-before-lock window

`Pipeline::Upload` PUTs the R2 object *before* `create_image` takes the storage lock. A sweep landing in between sees no row referencing that object and deletes it, leaving a row that points at nothing.

Phase A rated that acceptable because a 404 icon would self-heal on the next crawl. Phase A's own `unchanged?` short circuit then falsified that: the row keeps its `original_fingerprint`, so every later crawl stops before processing and never re-uploads. The 404 is permanent.

It has been unreachable so far because nothing schedules a content-addressed preset. Task 3 makes one reachable, and not exotically: two shows serving byte-identical artwork share one `storage_path`, so show A's art changing fires `ImageReplacementCollector` on exactly the path show B's concurrent crawl is uploading to.

**Files:**
- Modify: `app/jobs/image_crawler/pipeline/upload.rb`
- Test: `test/jobs/image_crawler/pipeline/upload_test.rb`

**Interfaces:**
- Consumes: `ImageCrawler::Image#storage_path`, `#r2_bucket`, `#r2_source_path` (Phase A).
- Produces: `Pipeline::Upload#ensure_stored` — HEADs the just-written object and re-uploads if it is gone. Called after `create_image`, inside the same `begin`/`rescue` so a failure degrades to legacy exactly as an R2 write failure already does.

**Why this ordering works.** A sweep holds the storage lock across its survivor check and its delete; `create_image` holds the same lock while writing the row. They are therefore serialized. If the sweep wins the lock it deletes, then `create_image` writes the row, then our HEAD finds the object gone and re-uploads — and no later sweep can delete it, because the row now exists. If `create_image` wins, the sweep sees the survivor and never deletes. Either way the object exists once the method returns.

- [ ] **Step 1: Write the failing test**

Append to `test/jobs/image_crawler/pipeline/upload_test.rb` (inside `class UploadTest`):

```ruby
      # The R2 PUT lands before create_image takes the storage lock, so a sweep
      # in between deletes an object nothing references yet. Once the row
      # exists no sweep can touch it, so one HEAD after attaching closes the
      # window -- and re-uploading is the only recovery, because unchanged?
      # would short-circuit every later crawl before it reprocessed.
      def test_should_re_upload_when_the_object_vanished_before_the_row_existed
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/cover.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
            provider: ::Image.providers[:entry_icon], provider_id: 5, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
          head = stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 404)

          Upload.new.perform(image.to_h)

          assert_requested head
          assert_requested put, times: 2
        end
      end

      def test_should_not_re_upload_when_the_object_is_still_there
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          processed_path = copy_support_file("image.jpeg")
          original_url = "http://example.com/cover.jpg"

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
            provider: ::Image.providers[:entry_icon], provider_id: 6, feed_id: 9,
            fingerprint: SecureRandom.hex(16),
            original_fingerprint: Digest::MD5.hexdigest("other bytes"),
            original_url: original_url, final_url: original_url,
            download_path: processed_path, processed_path: processed_path,
            bytesize: File.size(processed_path),
            width: 200, height: 200, placeholder_color: "0867e2"
          )

          stub_request(:put, /s3\.amazonaws\.com/)
          put = stub_request(:put, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
          stub_request(:head, "https://test-account.r2.cloudflarestorage.com/images-test/#{image.storage_path}")
            .to_return(status: 200)

          Upload.new.perform(image.to_h)

          assert_requested put, times: 1
        end
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/upload_test.rb
```

Expected: FAIL on the first test — no HEAD is issued, so WebMock reports the `head` stub was never requested. (The second test does not pass yet either — it references a method that does not exist until Step 3. It is the guard for the change you are about to make, not a currently-green test.)

Note the preset is `touch_icon`, not `podcast`. `podcast` does not become `unified`/`content_addressed` until Task 3, so until then it never reaches the R2 branch at all and neither test could pass. `touch_icon` is already both, and is also 200×200, so it exercises exactly the path under test.

- [ ] **Step 3: Add the check**

In `app/jobs/image_crawler/pipeline/upload.rb`, call it after `create_image`:

```ruby
        if @image.unified?
          begin
            upload_r2
            @image.create_image
            ensure_stored
            Librato.increment("image.r2_upload")
            r2_stored = true
```

and add the method next to `upload_r2`:

```ruby
      # create_image is the first moment a row references this object. Until
      # then a garbage-collection sweep sees the path as unreferenced and is
      # entitled to delete it -- and for a content-addressed preset that loss
      # is permanent, because unchanged? matches on the original bytes and
      # stops every later crawl before it reprocesses. The lock serializes the
      # sweep against create_image, so by the time we get here the answer is
      # settled: either the object survived, or it was deleted and no sweep can
      # delete it again.
      def ensure_stored
        Fog::Storage.new(STORAGE_R2).head_object(@image.r2_bucket, @image.storage_path)
      rescue Excon::Errors::NotFound
        Librato.increment("image.r2_resurrected")
        Sidekiq.logger.info "Upload: object vanished before the row existed, re-uploading id=#{@image.id} storage_path=#{@image.storage_path}"
        upload_r2
      end
```

If the installed fog version raises a different class for a 404 HEAD, the first test will show you which — widen the `rescue` to name that class as well. Do **not** replace it with a bare `rescue`: swallowing every error here would hide a genuine R2 outage as a silent re-upload.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/pipeline/upload_test.rb
```

Expected: PASS, including the pre-existing `test_should_dual_write_unified_images`, `test_should_degrade_to_legacy_when_r2_upload_fails`, and `test_should_store_icons_only_in_r2` — all three now issue a HEAD as well, and none of them stubs one, so if any fails with an unstubbed-request error, add a 200 HEAD stub to that test rather than changing what it asserts.

- [ ] **Step 5: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. Baseline is 1594 runs, 0 failures, 3 pre-existing skips; this task adds 2.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/pipeline/upload.rb test/jobs/image_crawler/pipeline/upload_test.rb && git commit -m "Re-upload an object a sweep removed before its row existed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Garbage collection harvests entry-owned icon rows

`ImageGarbageCollector#perform` starts from `Image.entry_images.where(provider_id: entry_ids)`, and `entry_images` is `%i[entry_link_preview entry_preview]`. Podcast episode art is `entry_icon`, which that scope excludes — so once Task 3 starts writing those rows, deleting an entry would leave both the row and its R2 object behind forever. This is the "fixes the episode-art deletion leak" the design doc promises.

**`entry_images` itself must not change.** `Dedupe` and `ReuseRules` use it, and its narrowness is exactly why an icon crawl can never dedupe onto an entry-preview row. Add a second scope for the collector.

**Files:**
- Modify: `app/models/image.rb` (add a scope next to `entry_images`)
- Modify: `app/jobs/image_garbage_collector.rb:20`
- Test: `test/jobs/image_garbage_collector_test.rb`

**Interfaces:**
- Consumes: `ImageGarbageCollector#orphaned_paths`, `#delete_r2_objects`, `Image.with_storage_locks` (Phase A).
- Produces: `Image.entry_owned` — `where(provider: %i[entry_link_preview entry_preview entry_icon])`. The rows an entry's deletion should take with it. `Image.entry_images` is unchanged and keeps its existing three callers.

- [ ] **Step 1: Write the failing test**

Append to `test/jobs/image_garbage_collector_test.rb`:

```ruby
  # Episode artwork is provider entry_icon and is owned by the entry, so
  # deleting the entry must take the row and its object. entry_images
  # deliberately excludes entry_icon -- Dedupe and ReuseRules rely on that --
  # so the collector needs its own, wider scope.
  test "collects an entry's icon row along with its preview rows" do
    with_env("R2_BUCKET_IMAGES" => "images-test") do
      icon_url = "http://example.com/cover.jpg"
      icon = Image.create!(
        provider: :entry_icon, provider_id: "1", feed_id: 9,
        url: icon_url, variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg"),
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )
      stub_batch_delete

      assert_difference -> { Image.count }, -1 do
        ImageGarbageCollector.new.perform([1])
      end

      assert_requested :post, "https://test-account.r2.cloudflarestorage.com/images-test/?delete", times: 1 do |request|
        request.body.include?(icon.storage_path)
      end
    end
  end

  # The narrow scope is load-bearing elsewhere: widening it would let an icon
  # crawl dedupe onto an entry-preview row. Asserted behaviourally rather than
  # by inspecting where_values_hash, which holds cast enum integers.
  test "entry_images excludes icon rows while entry_owned includes them" do
    icon = Image.create!(
      provider: :entry_icon, provider_id: "77", feed_id: 9,
      url: "http://example.com/cover.jpg", variant: "200x200",
      image_fingerprint: SecureRandom.hex(16),
      original_fingerprint: SecureRandom.hex(16),
      storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg"),
      width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
    )

    refute_includes Image.entry_images, icon
    assert_includes Image.entry_owned, icon
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_garbage_collector_test.rb
```

Expected: FAIL on the first test — the `entry_icon` row is not harvested, so `Image.count` does not change and no delete is requested. The second test does not pass yet either — it references `Image.entry_owned`, which does not exist until Step 3, so it raises NoMethodError. It is the guard for the change you are about to make, not a currently-green test.

- [ ] **Step 3: Add the scope**

In `app/models/image.rb`, directly below the existing `entry_images` line:

```ruby
  scope :entry_images, -> { where(provider: %i[entry_link_preview entry_preview]) }

  # What an entry's deletion takes with it. Wider than entry_images because
  # episode artwork (entry_icon) is entry-owned too. These are deliberately
  # two scopes, not one: entry_images is also Dedupe's and ReuseRules' lookup
  # scope, and its narrowness is what stops an icon crawl from deduping onto
  # an entry-preview row.
  scope :entry_owned, -> { where(provider: %i[entry_link_preview entry_preview entry_icon]) }
```

- [ ] **Step 4: Point the collector at it**

In `app/jobs/image_garbage_collector.rb`, line 20:

```ruby
    rows = Image.entry_owned.where(provider_id: entry_ids).to_a
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_garbage_collector_test.rb test/jobs/entry_deleter_test.rb test/jobs/image_crawler
```

Expected: PASS. `entry_deleter_test.rb` is the production caller and proves the deletion path still works end to end; the `image_crawler` directory proves `Dedupe`/`ReuseRules` are untouched.

- [ ] **Step 6: Commit**

```bash
git add app/models/image.rb app/jobs/image_garbage_collector.rb test/jobs/image_garbage_collector_test.rb && git commit -m "Collect entry-owned icon rows when an entry is deleted

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Podcast presets become unified and content-addressed

Flip the two presets in. After this, a podcast crawl writes an `images` row and an R2 object alongside the legacy S3 object it already writes, and a re-crawl whose bytes are unchanged costs one download and nothing else.

**Files:**
- Modify: `app/jobs/image_crawler/lib/image.rb` (`PRESETS[:podcast]`, `PRESETS[:podcast_feed]`)
- Test: `test/jobs/image_crawler/image_test.rb`, `test/jobs/image_crawler/pipeline/find_test.rb`

**Interfaces:**
- Consumes: `content_addressed?`, `legacy_store?`, `unified?` (Phase A); `Pipeline::Find#attempt_icon` and `#unchanged?`; `Pipeline::Process`'s `unified? && !content_addressed?` branch.
- Produces: `PRESETS[:podcast]` and `PRESETS[:podcast_feed]` each gain `unified: true, content_addressed: true, legacy_store: true`. Everything else about them — `width: 200, height: 200, minimum_size: nil, crop: :fill_crop, format: "jpg", validate: true`, and their `job_class` — is unchanged.

**What each flag buys, and why `legacy_store` stays true.** `unified` writes the row and the R2 object. `content_addressed` routes `Find` to `attempt_icon`, which never consults `Dedupe` (right for a source that can serve new bytes at a stable URL) and short-circuits on an unchanged `original_fingerprint`. `legacy_store: true` keeps the S3 PUT, because `entries.media_image` and `feeds.custom_icon` are still the fallback read path until a later phase retires them — this is dual-store, and dropping it now would blank artwork for every reader on the old path.

Note `Process` sends content-addressed presets through a single `crop!` rather than `crop_pair!`, so this produces one jpg, which is what both R2 and S3 receive.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/image_test.rb`:

```ruby
    # One object per show instead of one per episode: a show and every episode
    # reusing the same artwork fingerprint to the same storage_path, across
    # both presets, because they share a variant and a format.
    test "podcast presets are content-addressed and share objects across show and episode" do
      fingerprint = Digest::MD5.hexdigest("cover bytes")
      build = ->(preset, provider, url) {
        Image.new_with_attributes(
          id: SecureRandom.hex, preset_name: preset, image_urls: [],
          provider: ::Image.providers[provider], provider_id: 1,
          original_url: url, original_fingerprint: fingerprint
        )
      }

      episode = build.call("podcast", :entry_icon, "http://example.com/ep1.jpg")
      show = build.call("podcast_feed", :feed_icon, "http://example.com/show.jpg")

      assert episode.content_addressed?
      assert episode.legacy_store?, "the legacy S3 object is still the fallback read path"
      assert_equal "200x200", episode.variant
      assert_equal "jpg", episode.preset.format
      assert_equal :fill_crop, episode.preset.crop
      assert_equal ::Image.content_storage_path_for(fingerprint, "200x200", "jpg"), episode.storage_path
      assert_equal episode.storage_path, show.storage_path
    end

    # touch_icon is also 200x200 but renders png through a different recipe.
    # The extension is what keeps the two object keys apart.
    test "podcast artwork does not collide with touch_icon at the same variant" do
      fingerprint = Digest::MD5.hexdigest("cover bytes")
      podcast = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "podcast", image_urls: [],
        provider: ::Image.providers[:entry_icon], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: fingerprint
      )
      touch = Image.new_with_attributes(
        id: SecureRandom.hex, preset_name: "touch_icon", image_urls: [],
        provider: ::Image.providers[:feed_icon], provider_id: 1,
        original_url: "http://example.com/a.jpg", original_fingerprint: fingerprint
      )

      assert_equal "200x200", touch.variant
      refute_equal podcast.storage_path, touch.storage_path
    end
```

Append to `test/jobs/image_crawler/pipeline/find_test.rb`:

```ruby
      # Podcast artwork can change under a stable URL, so Dedupe's
      # skip-the-download shortcut is wrong for it: always fetch, then
      # short-circuit on the original bytes.
      def test_should_short_circuit_unchanged_podcast_artwork
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          original_url = "http://example.com/cover.jpg"
          stub_request_file("image.jpeg", original_url, headers: {content_type: "image/jpeg"})
          fingerprint = Digest::MD5.file(support_file("image.jpeg")).hexdigest

          row = ::Image.create!(
            provider: :entry_icon, provider_id: "5", feed_id: 9,
            url: original_url, variant: "200x200",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: fingerprint,
            storage_path: ::Image.content_storage_path_for(fingerprint, "200x200", "jpg"),
            width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc",
            updated_at: 1.year.ago
          )
          expected_updated_at = row.updated_at

          image = Image.new_with_attributes(
            id: SecureRandom.hex, preset_name: "podcast", image_urls: [original_url],
            provider: ::Image.providers[:entry_icon], provider_id: 5, feed_id: 9
          )

          assert_no_difference -> { Process.jobs.size } do
            Find.new.perform(image.to_h)
          end
          assert_requested :get, original_url
          assert_equal expected_updated_at.to_f, row.reload.updated_at.to_f
        end
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/pipeline/find_test.rb
```

Expected: FAIL — `content_addressed?` is false for `podcast`, so `storage_path` is URL-derived (the show and episode paths differ), and `Find` routes to `attempt_legacy` rather than short-circuiting.

- [ ] **Step 3: Flip the presets in**

In `app/jobs/image_crawler/lib/image.rb`, replace the two preset hashes:

```ruby
      podcast: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        format: "jpg",
        validate: true,
        unified: true,
        content_addressed: true,
        legacy_store: true,
        job_class: ItunesImage
      },
      podcast_feed: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :fill_crop,
        format: "jpg",
        validate: true,
        unified: true,
        content_addressed: true,
        legacy_store: true,
        job_class: ItunesFeedImage
      },
```

`legacy_store: true` is written explicitly even though `preset.legacy_store != false` already defaults to true for a missing key. These are the first presets where dual-store is a deliberate, temporary transition state rather than the permanent arrangement, and the next person to read this hash should see that without having to reason about the default.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler
```

Expected: PASS, including `itunes_image_test.rb`, whose scheduling assertions are unaffected by these flags.

- [ ] **Step 5: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/image_crawler/lib/image.rb test/jobs/image_crawler && git commit -m "Store podcast artwork by the fingerprint of its original bytes

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Episode artwork reads the row first

The row now exists; nothing reads it. `Entry#itunes_image` still returns the legacy S3 URL out of `entries.media_image`. Give it the same row-first shape `Entry#processed_image` already has for entry previews.

**Files:**
- Modify: `app/models/image.rb` (extract `Image.r2_url`)
- Modify: `app/models/entry.rb` (association, `itunes_image`, `r2_image_url`)
- Modify: `app/jobs/image_crawler/itunes_image.rb`
- Test: `test/models/entry_test.rb`, `test/jobs/image_crawler/itunes_image_test.rb`

**Interfaces:**
- Consumes: `PRESETS[:podcast]` writing `provider: entry_icon` rows (Task 3).
- Produces:
  - `Image.r2_url(storage_path) -> String | nil` — builds the public R2 URL, or nil when `R2_IMAGE_HOST` is unset. Moved verbatim from `Entry#r2_image_url`, which becomes a one-line delegation so both models share one implementation.
  - `Entry#icon_image_record` — `has_one`, scoped `provider_entry_icon`.
  - `Entry#itunes_image` — prefers the row, falls back to the existing legacy logic unchanged.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/entry_test.rb`:

```ruby
  test "itunes_image prefers the stored row over the legacy url" do
    with_env("R2_IMAGE_HOST" => "images.example.com", "ENTRY_IMAGE_HOST" => "legacy.example.com") do
      feed = create_feeds(users(:ben)).first
      entry = create_entry(feed)
      entry.update!(media_image: "https://old.example.com/abc/cover.jpg")

      assert_match "legacy.example.com", entry.itunes_image

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :entry_icon, provider_id: entry.id.to_s, feed_id: feed.id,
        url: "http://example.com/cover.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Entry.find(entry.id).itunes_image
    end
  end

  test "itunes_image is nil when there is neither a row nor a legacy url" do
    feed = create_feeds(users(:ben)).first
    assert_nil create_entry(feed).itunes_image
  end
```

Replace the "updates the entry when an image hash is given" test in `test/jobs/image_crawler/itunes_image_test.rb` with the pair below. Its behavior genuinely splits in two now, and the row-backed half is the new one:

```ruby
    test "updates the entry when a legacy-only image hash is given" do
      processed_url = "https://cdn.example.com/cover.jpg"

      ItunesImage.new.perform(@entry.public_id, {"processed_url" => processed_url})

      @entry.reload
      assert_equal processed_url, @entry.media_image
      assert_equal "entry_icon", @entry.provider
      assert_equal @entry.id.to_s, @entry.provider_id
    end

    # Row-backed: Upload already wrote the images row before enqueueing this
    # callback, so the metadata is not duplicated onto the entry. media_image
    # keeps its legacy value for readers still on the fallback path.
    test "keeps writing the legacy url and touches the entry when row-backed" do
      processed_url = "https://cdn.example.com/cover.jpg"
      @entry.update!(updated_at: 1.year.ago)
      before = @entry.reload.updated_at

      ItunesImage.new.perform(@entry.public_id, {
        "processed_url" => processed_url,
        "storage_path" => "abc/abc123.jpg"
      })

      @entry.reload
      assert_equal processed_url, @entry.media_image
      assert_operator @entry.updated_at, :>, before
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb test/jobs/image_crawler/itunes_image_test.rb
```

Expected: FAIL — `itunes_image` returns the legacy URL even with a row present, and `Image.r2_url` does not exist.

- [ ] **Step 3: Give `Image` the URL builder**

In `app/models/image.rb`, add below `content_storage_path_for`:

```ruby
  # The public URL for a stored object. Nil until R2_IMAGE_HOST is set, which
  # is what keeps the read path on the legacy fallback during a transition.
  def self.r2_url(storage_path)
    return nil if storage_path.blank?
    host = ENV["R2_IMAGE_HOST"]
    return nil if host.blank?
    host = "https://#{host}" unless host.match?(%r{\Ahttps?://})
    [host.chomp("/"), storage_path].join("/")
  end
```

In `app/models/entry.rb`, replace the body of the existing private `r2_image_url` so there is one implementation rather than two:

```ruby
  def r2_image_url(storage_path)
    Image.r2_url(storage_path)
  end
```

- [ ] **Step 4: Read the row first**

In `app/models/entry.rb`, add the association next to the existing image associations:

```ruby
  has_one :icon_image_record, -> { provider_entry_icon }, class_name: "Image", foreign_key: :provider_id
```

and replace `itunes_image`:

```ruby
  def itunes_image
    r2_itunes_image || legacy_itunes_image
  end

  # New artwork lives on the images row; episodes crawled before the R2
  # transition keep their settings value. Reads prefer the row, then fall back.
  def r2_itunes_image
    r2_image_url(icon_image_record&.storage_path)
  end

  def legacy_itunes_image
    if media_image || (data && data["itunes_image_processed"])
      image_url = media_image || data["itunes_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end
```

- [ ] **Step 5: Touch on the row-backed path**

In `app/jobs/image_crawler/itunes_image.rb`, replace `receive`:

```ruby
    def receive
      # media_image stays written either way: it is still the fallback read
      # path until the legacy store retires, and one write per episode is not
      # a fan-out worth avoiding.
      #
      # The touch is not redundant with that update. The legacy S3 key comes
      # from image_name, which is built from the job id ("<public_id>-itunes")
      # and is therefore stable no matter what the bytes are -- new artwork
      # overwrites the same key and yields the same processed_url, so the
      # update no-ops and bumps nothing. Without the touch, artwork that
      # changed would leave every cached view keyed on this entry stale.
      @entry.update(
        media_image: @image["processed_url"],
        provider: Entry.providers[:entry_icon],
        provider_id: @entry.id
      )
      @entry.touch if @image["storage_path"]
    end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/entry_test.rb test/jobs/image_crawler/itunes_image_test.rb test/presenters
```

Expected: PASS. Note `test/presenters` does **not** in fact cover `EntryPresenter#media_image` — that directory holds only an XSS test, and no test anywhere exercises the `entry.itunes_image || entry.feed.custom_icon` fallback. This task adds a real presenter test for all three branches of it. (An earlier draft justified that by claiming Task 5 changes the other half of the expression — it does not: Task 5 adds a new `Feed#icon_url` and leaves `custom_icon` and the presenter untouched. The test earns its place on the zero-coverage gap alone.)

- [ ] **Step 7: Commit**

```bash
git add app/models/image.rb app/models/entry.rb app/jobs/image_crawler/itunes_image.rb test/models/entry_test.rb test/jobs/image_crawler/itunes_image_test.rb && git commit -m "Read episode artwork from the images row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Show artwork reads the row first

Same move for the feed. This one has an extra wrinkle: `FaviconComponent` wraps the legacy URL in `RemoteFile.signed_url` — a signed proxy — and an R2 URL must not be wrapped, because it is already served from our own CDN.

**Files:**
- Modify: `app/models/feed.rb` (association, `icon_url`)
- Modify: `app/views/components/favicon_component.rb`
- Modify: `app/jobs/image_crawler/itunes_feed_image.rb`
- Test: `test/models/feed_test.rb`, `test/components/favicon_component_test.rb` (exists — append to it)

**Interfaces:**
- Consumes: `Image.r2_url` (Task 4); `PRESETS[:podcast_feed]` writing `provider: feed_icon` rows (Task 3).
- Produces:
  - `Feed#icon_image_record` — `has_one`, scoped `provider_feed_icon`.
  - `Feed#icon_url -> String | nil` — the renderable URL: the row's R2 URL when one exists, otherwise `RemoteFile.signed_url(icon)`, otherwise nil. `Feed#icon`, `#icon_options`, and `#default_icon_format` are **unchanged**; `icon_url` sits in front of them.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/feed_test.rb`:

```ruby
  test "icon_url prefers the stored row and does not sign it" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = create_feeds(users(:ben)).first
      feed.update!(custom_icon: "https://old.example.com/abc/show.jpg")

      assert_match "/files/icons/", feed.icon_url, "the legacy path is proxied through a signed url"

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: feed.id.to_s, feed_id: feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Feed.find(feed.id).icon_url
    end
  end

  test "icon_url is nil when the feed has no icon at all" do
    assert_nil create_feeds(users(:ben)).first.icon_url
  end
```

Append to the existing `test/components/favicon_component_test.rb`. Its `setup` already assigns `@feed = feeds(:daring_fireball)`, and the file's idiom is `output = render FaviconComponent.new(...)` followed by `output.to_s` — match it:

```ruby
  test "feed icon from the stored row is served directly, not through the proxy" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, "https://images.example.com/#{path}"
      refute_includes output.to_s, "/files/icons/",
        "an R2 url is already on our own CDN and must not be wrapped in the signing proxy"
    end
  end

  # The branch cannot key on custom_icon: once the legacy store retires, a
  # row-backed feed has artwork and no custom_icon at all.
  test "feed icon renders from the row even with no custom_icon" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      assert_nil @feed.custom_icon

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: @feed.id.to_s, feed_id: @feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(@feed.id))

      assert_includes output.to_s, path
    end
  end
```

**The file's existing `"feed icon"` test must stay green untouched.** It sets `@feed.custom_icon` with no row present and asserts the exact signed-proxy markup — which is precisely the fallback `icon_url` preserves. If that test fails, `icon_url`'s fallback is wrong; fix `icon_url`, not the test.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/components/favicon_component_test.rb
```

Expected: FAIL — `Feed#icon_url` does not exist.

- [ ] **Step 3: Add the association and the resolver**

In `app/models/feed.rb`, next to the existing `has_one :favicon`:

```ruby
  has_one :icon_image_record, -> { provider_feed_icon }, class_name: "Image", foreign_key: :provider_id
```

and add, next to `icon`:

```ruby
  # The renderable URL for the feed's own icon. New artwork lives on the
  # images row and is served straight from our CDN; anything crawled before
  # the R2 transition is a third-party url that still has to go through the
  # signing proxy. icon/icon_options/default_icon_format are untouched -- they
  # still answer "which source won and what shape is it", which is a different
  # question from "what do I put in the src attribute".
  def icon_url
    Image.r2_url(icon_image_record&.storage_path) || (icon && RemoteFile.signed_url(icon))
  end
```

- [ ] **Step 4: Render from it**

In `app/views/components/favicon_component.rb`, change the branch condition and the render. The condition must move off `@feed.icon`, because a feed first crawled after the cutover has a row but no `custom_icon`:

```ruby
    def view_template(&)
      if @feed.newsletter?
        icon_newsletter
      elsif @feed.twitter_user?
        icon_twitter_user
      elsif @feed.icon_url
        icon_feed
      elsif @feed.pages? && @entry
        icon_pages
      elsif @feed.pages?
        icon_pages_default
      elsif @feed.favicon&.cdn_url
        icon_favicon(@feed.favicon)
      else
        icon_generated
      end
    end
```

and in `icon_feed`, render the resolved URL instead of signing `@feed.icon` again:

```ruby
    def icon_feed
      span class: "favicon-wrap twitter-profile-image icon-format-#{@feed.custom_icon_format || @feed.default_icon_format}" do
        image_tag_with_fallback(
          image_url("favicon-profile-default.png"),
          @feed.icon_url,
          alt: ""
        )
      end
    end
```

- [ ] **Step 5: Touch on the row-backed path**

In `app/jobs/image_crawler/itunes_feed_image.rb`, replace `receive`:

```ruby
    def receive
      # custom_icon stays written either way: it is still the fallback read
      # path until the legacy store retires, and it is what icon_options reads
      # to decide the icon's shape.
      #
      # The touch is not redundant with that update. The legacy S3 key comes
      # from image_name, built from the job id, whose only variable part is a
      # digest of the *source url* -- so a show that replaces its artwork at
      # the same url overwrites the same key, yields the same processed_url,
      # and the update no-ops. Without the touch, the sidebar and every entry
      # summary for this feed would keep serving the old artwork.
      @feed.update(custom_icon: @image["processed_url"], custom_icon_format: "square")
      @feed.touch if @image["storage_path"]
    end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/components test/views test/controllers
```

Expected: PASS. The component, view, and controller suites are what prove the branch change did not disturb icon rendering for newsletters, Twitter feeds, Pages feeds, or favicon-only feeds.

- [ ] **Step 7: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/models/feed.rb app/views/components/favicon_component.rb app/jobs/image_crawler/itunes_feed_image.rb test/models/feed_test.rb test/components/favicon_component_test.rb && git commit -m "Read show artwork from the images row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Manual verification before merge

The suite covers the mechanics. These need eyes.

- [ ] **A real podcast, end to end.** In `bin/rails console`, pick a podcast feed with `itunes_image` in its options and run `ImageCrawler::ItunesFeedImage.perform_async(feed.id)` with a Sidekiq worker running. Then confirm the row and that both stores got an object:

```ruby
feed = Feed.where("options->>'itunes_image' IS NOT NULL").first
row = Image.find_by(provider: :feed_icon, provider_id: feed.id.to_s)
[row&.storage_path, row&.width, row&.height, row&.original_fingerprint, feed.reload.custom_icon.present?]
```

Confirm `storage_path` ends in `.jpg`, the dimensions are 200×200 or smaller, and `custom_icon` is still set — dual-store means both, and a missing `custom_icon` would blank artwork for readers on the fallback path.

- [ ] **The short circuit actually short-circuits.** Run the same job a second time and confirm no new `Process` job is enqueued and `row.reload.updated_at` is unchanged. That is the whole point of content-addressing, and it is the behavior that silently regresses if `unchanged?` ever stops matching.

- [ ] **The dedup win is real.** For a show whose episodes reuse the show artwork, confirm the episode rows and the feed row share one `storage_path`:

```ruby
Image.where(provider: [:entry_icon, :feed_icon], feed_id: feed.id).distinct.count(:storage_path)
```

Expect 1 for a show that uses one image throughout — that is "one object per show instead of one per episode" made visible.

- [ ] **Artwork renders in the browser.** Sign in at `https://feedbin.resolv.app/auto_sign_in`, open a podcast feed, and confirm the show icon in the sidebar and the episode artwork in the audio player both appear. Set `R2_IMAGE_HOST` and confirm they switch to the R2 host; unset it and confirm they fall back to the signed proxy without breaking.

## Deployment notes

`R2_IMAGE_HOST` is the read cutover switch, and it is shared with entry previews — it is already set if Phase 1 has been cut over. `Image.r2_url` returns nil without it, so rows accumulate and reads stay on the legacy path until it is set.

Deploy order is code first, then let rows accumulate, then verify. There is no migration in this plan and no cache-key version bump, so no cold-cache wave.

One new cost to watch: Task 1 adds a HEAD request to **every** unified upload, entry previews included, not just podcast artwork. That is deliberate — the window it closes is equally permanent for entry previews, which never re-crawl. If the added request rate proves to matter, scoping it to `@image.content_addressed?` is a one-line change, at the cost of leaving the entry-preview window open.

## What this plan deliberately leaves out

- **The legacy store stays.** `legacy_store: true`, `entries.media_image`, and `feeds.custom_icon` all keep being written. Retiring them is a separate phase that needs the rows to bake first, and it is the phase that will need the touch-only callbacks and the cache-key changes this plan skips.
- **`entries.provider` / `entries.provider_id`** are still written by `ItunesImage#receive` and still read by nothing (`rg "Entry.providers\[:entry_icon\]"` finds one writer and no readers). Removing them is unrelated cleanup.
- **The `podcast` and `podcast_feed` presets remain separate** even though they are now byte-identical in every field but `job_class`. Merging them would change the `preset_name` recorded in `images.data`, and they diverge again the moment either tenant wants a different geometry.
- **`Feed#default_icon_format` is not made row-aware.** It derives the icon's shape from `icon_options`, whose first key is `custom_icon` — so a feed with a row but no `custom_icon` renders `class="icon-format-"` with nothing after the dash. Unreachable while `legacy_store` is on, because `ItunesFeedImage#receive` always writes `custom_icon` and `custom_icon_format: "square"` together. It becomes reachable the moment the legacy store retires, and that is the phase that should fix it — by then the row is the only source and the shape can come from the preset.
- **Phases D and E** — YouTube channel avatars and favicons/touch icons — are untouched. Phase E in particular still depends on `website_favicon` and `website_touch_icon` being **separate providers**, which is now load-bearing for `unchanged?`, not just for row layout.
