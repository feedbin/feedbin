# Icon Family Phase E — Favicons and Touch Icons (Dual-Write) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `FaviconCrawler::Finder` feed the shared image pipeline alongside everything it already does, so an `images` row and an R2 object accumulate for every host's favicon **and**, as a separate provider, its apple-touch-icon — and re-enable the conditional HTTP requests that have been switched off since November 2025, now that each row owns the validators for its own URL.

**Architecture:** Pure dual-store. The `favicons` row, its base64 column, and its S3 object keep being written exactly as they are today; the pipeline produces a parallel `images` row and R2 object from the same page fetch. **Nothing reads the new rows.** Two new providers (`website_favicon`, `website_touch_icon`) keyed by host, using the `favicon` and `touch_icon` presets that Phase A already built and nothing has ever scheduled. `ImageCrawler::Download` gains conditional-request support so `Pipeline::Find` can send `If-None-Match`/`If-Modified-Since` — but only when re-fetching the exact URL the row came from, which is the constraint that makes a 304 mean what the code assumes it means.

**Tech Stack:** Rails 8.1, Sidekiq, Down (HTTP downloads), Fog::Storage (R2 is S3-compatible), libvips via ImageProcessing::Vips, Nokogiri, Postgres, minitest + webmock.

**Design doc:** `docs/superpowers/specs/2026-08-13-icon-family-design.md` — especially "The conditional request is disabled today, and the new schema is what un-blocks it", the per-tenant map, and both retrospective sections ("What Phases A and B learned", "What Phase D learned").

**Predecessors:** Phases A–D, all on this branch. This plan consumes `Processor::IconLayer`, `Image.content_storage_path_for`, `Image.with_storage_lock`, `Pipeline::Find#attempt_icon`/`#unchanged?`, `Upload#ensure_stored`, `ImageReplacementCollector`, and the `favicon`/`touch_icon` presets — all already built and tested.

## Scope: this is the dual-write half only

The design doc sequences Phase E as "dual-write until rows have accumulated → flip the read → bake → retire the legacy crawler, its bucket, and the `favicons` table." **Accumulate** and **bake** are elapsed-time gates spanning deploys, so they cannot be crossed inside one execution. This plan stops at the first gate.

**Phase F** — a separate plan, written after these rows have accumulated in production — flips the reads (`FaviconComponent`, `EntriesHelper.entry_favicon`, `ApplicationHelper#favicon_with_host`, and **both API v2 endpoints**), then retires the crawler, the bucket, and the table. See "What Phase F must solve" at the end; one of its problems is not yet solved and you should read it before assuming the retirement is straightforward.

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`. A single test: `bin/rails test <path> -n <name>`.
- **Test baseline entering this plan: 1653 runs, 4022 assertions, 0 failures, 0 errors, 3 skips.** Each task states how many runs it adds.
- **A rare pre-existing flake exists: roughly 1 run in 20 fails with the assertion count unchanged** (e.g. `1653 runs, 4022 assertions, 1 failures`). It is not caused by this work. The diagnostic is the assertion count: if it is identical to a clean run, no test aborted early, so the failure is one wrong comparison somewhere — re-run before investigating. If the assertion count *moves*, that is yours.
- **NEVER interpolate values into SQL strings** — hash conditions, bound parameters, or `sanitize_sql_array` only.
- **`Image.provider` additions are append-only. NEVER renumber** — the column stores the integer. `website_favicon` is 6, `website_touch_icon` is 7.
- **`website_favicon` and `website_touch_icon` must stay separate providers.** `Pipeline::Find#unchanged?` keys on `(provider, provider_id, original_fingerprint, variant)` and the `(provider, provider_id)` index is unique. One shared provider for a host would let whichever preset ran last own `original_fingerprint`, and the other would short-circuit forever on a fingerprint belonging to a different variant's object.
- **Do not change `Cropper#icon_crop`'s scaling.** `channel_avatar` (Phase D) shares a `storage_path` with `touch_icon` whenever source bytes are identical — both are 200×200 PNG, content-addressed. `test_icon_crop_and_limit_png_agree_on_a_single_layer_source` is the invariant that makes that safe, and it pins single-layer sources only.
- **Do not change any existing preset's behavior.** `favicon` and `touch_icon` already exist in `PRESETS` with the right values; this plan schedules them, it does not edit them.
- **The legacy path must keep behaving exactly as it does today.** Every existing test in `test/jobs/favicon_crawler/finder_test.rb` must stay green **without being edited**.
- **The touch rule still governs.** An `images` row's `updated_at` may change only when the stored bytes change.
- All pipeline jobs remain `retry: false`.
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## Decisions this plan makes that the design doc left open

**1. `Etag`/`Last-Modified` are written with `update_column`, and `updated_at` is redefined as a content-version marker.** The design doc flags this as unresolved: `images.data` is the right home for the validators, but writing `data` bumps `updated_at`, which Phase B made a view cache key — so a host that returns a fresh `ETag` for identical bytes (every static site that rebuilds) would invalidate every view referencing its icon.

The resolution is `update_column`, and the design doc's worry about it is backwards. It frets that "the row's `updated_at` no longer tells the whole truth about when the row last changed" — but the touch rule already *demands* exactly that: `updated_at` may move only when the bytes move. Skipping the timestamp for a validators-only write is not a compromise of the rule, it is the rule. State it wherever it is relied on: **`images.updated_at` is a content version, not a row mtime.**

**2. Conditional requests extend `ImageCrawler::Download` rather than swapping in `Feedkit::Request`.** The legacy crawler uses `Feedkit::Request.download`, which already supports `etag:`/`last_modified:` and exposes `not_modified?` — tempting to reuse. Rejected: it would fork the pipeline's download path for one preset family, losing `Download`'s size cap, timeouts, camo handling, and per-provider dispatch, and creating exactly the drift the design doc warns about for `IconLayer`. `Down` supports custom request headers, and — on the `:http` backend this app configures (`config/initializers/down.rb`) — reports a 304 as `Down::ResponseError` with `response.code == "304"`; both verified against the installed gems before writing this plan. That last fact is backend-specific: the `:net_http` backend instead raises `Down::NotModified`, a sibling of `Down::ResponseError` under `Down::Error`, not a subtype of it, so a bare `rescue Down::ResponseError` would not catch it on that backend and a 304 would fall through to `Download::Default`'s blanket `rescue Down::Error` with `not_modified?` silently staying false. Using an exception for an expected outcome is mildly ugly; it is contained in two rescues (one per backend's exception) with a shared comment.

Because it lands in shared `Download`/`Pipeline::Find` code rather than anything favicon-specific, the blast radius is wider than "the icon family" suggests. `Pipeline::Find#attempt_icon` — and therefore conditional requests, the 304 handling, and `validators_for`/`store_validators` — is reached by every `content_addressed?` preset, not only `favicon`/`touch_icon`: `podcast`, `podcast_feed`, and `channel_avatar` as well, all three already shipped and serving traffic. This phase changes fetch behavior and `images.data` contents for those three tenants too, not just the two it adds. See the Deployment notes and "What Phase F must solve" for the consequence.

**3. Favicon rows are never garbage collected — a stated decision, not an oversight.** `ImageGarbageCollector` harvests from entry ids and `Image.entry_owned` excludes both new providers. A row keyed by a **host** is owned by nothing that gets deleted: hosts are not records. `ImageReplacementCollector` still reclaims the old object whenever an icon's bytes change, which is the common case and the one that would otherwise grow without bound. What accumulates is one row plus one small PNG per host ever crawled. This is the same shape as Phase D's channel rows, whose storage cost was assessed and accepted.

**4. The design doc is wrong that `favicons.favicon` is dead.** It records "`favicons.favicon` (base64) is dead and ignored" as a settled decision. It is not: `app/controllers/api/v2/favicons_controller.rb` deliberately uses `Favicon.unscoped` to bypass the default scope that hides that column, and `app/views/api/v2/favicons/index.json.jbuilder` emits it as `favicon`. `/v2/icons` serves `cdn_url` off the same table. Both are public API endpoints with tests. This does not affect the present plan — nothing here changes a read — but it is a live blocker for the retirement, and the design doc's claim should not be trusted by whoever writes Phase F.

---

### Task 1: The two providers, and the size distinction a fill-only world never exercised

`Image.provider` gains the two host-scoped providers. This task pins **provider separation**, not the variant/recipe distinction: "`variant` names the rendering recipe, not the result" is already pinned for both icon presets by the pre-existing `test/jobs/image_crawler/image_test.rb:106` test, `"icon presets keep their recipe as the variant and store png"` — its comment already uses the same 180×180 touch_icon example, so a second test asserting `small.variant == "200x200"` here would be redundant and, worse, cannot even fail on this task's own deliverable: `variant` and `storage_path` never consult `provider`, so such a test would pass identically whether the new enum values existed or not. What this task's tests must guard, and do guard, is that `website_favicon` and `website_touch_icon` are two distinct provider values producing two distinct rows and two distinct storage objects for the same host — the reason that separation is load-bearing for `Pipeline::Find#unchanged?` is explained in the enum comment added in Step 3 below.

**Files:**
- Modify: `app/models/image.rb` (enum only)
- Test: `test/jobs/image_crawler/image_test.rb`, `test/jobs/image_crawler/processor/cropper_test.rb`

**Interfaces:**
- Consumes: `PRESETS[:favicon]` and `PRESETS[:touch_icon]` (Phase A, unchanged); `Image.content_storage_path_for` (Phase A); `Cropper#icon_crop` (Phase A).
- Produces: `Image.providers[:website_favicon] == 6`, `Image.providers[:website_touch_icon] == 7`, and the `provider_website_favicon` / `provider_website_touch_icon` scopes Rails generates from the `prefix: true` enum.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/image_test.rb`, inside `class ImageTest`:

```ruby
    # One host, two icons, two rows. The separation is load-bearing for
    # correctness, not layout: Pipeline::Find#unchanged? keys on (provider,
    # provider_id, original_fingerprint, variant) and (provider, provider_id)
    # is unique, so a shared provider would let whichever preset ran last own
    # the fingerprint and short-circuit the other forever.
    test "a host's favicon and touch icon are separate rows and separate objects" do
      fingerprint = Digest::MD5.hexdigest("icon bytes")
      build = ->(preset, provider) {
        Image.new_with_attributes(
          id: "a", preset_name: preset, image_urls: [],
          provider: ::Image.providers[provider], provider_id: "example.com",
          original_url: "http://example.com/icon.png", original_fingerprint: fingerprint
        )
      }

      favicon = build.call("favicon", :website_favicon)
      touch   = build.call("touch_icon", :website_touch_icon)

      assert_equal "32x32", favicon.variant
      assert_equal "200x200", touch.variant
      refute_equal favicon.storage_path, touch.storage_path
      refute_equal favicon.provider, touch.provider
    end
```

Append to `test/jobs/image_crawler/processor/cropper_test.rb`, inside `class CropperTest` (it already has a `write_solid_png` helper from Phase D — reuse it, do not redefine it):

```ruby
      # The other half of "variant names the recipe": icon_crop is a limit
      # crop, so the 200x200 touch_icon preset leaves a 180x180 source alone.
      # Upscaling would fabricate no detail and only make a larger, equally
      # soft file.
      def test_icon_crop_should_not_upscale_a_small_source
        file = write_solid_png(180, 180, [40, 90, 200])
        cropper = Processor::Cropper.new(file, crop: :icon_crop, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(180, image.width)
        assert_equal(180, image.height)
        assert_equal("png", image.extension)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/processor/cropper_test.rb
```

Expected: a mixed RED step, one failure not two. The `image_test.rb` test `"a host's favicon and touch icon are separate rows and separate objects"` FAILS — `::Image.providers[:website_favicon]` and `::Image.providers[:website_touch_icon]` both resolve to nil before Step 3, so `favicon.provider` and `touch.provider` are both nil and `refute_equal favicon.provider, touch.provider` fails on `nil == nil`. The `cropper_test.rb` test passes already: `icon_crop` uses `resize_to_limit`, so no-upscale is existing behavior, not something this task changes. **That is fine and expected** — it is a characterization test pinning behavior a later phase must not change, not a red-to-green step. Note in your report which of the two actually failed.

- [ ] **Step 3: Add the providers**

In `app/models/image.rb`, append to the enum. **Append-only — never renumber**, the column stores the integer:

```ruby
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
    embed_icon:         5,     # embed-provider icon keyed by that provider's own id (YouTube channel avatars)
    website_favicon:    6,     # a host's favicon, keyed by host ("medium.com")
    website_touch_icon: 7,     # a host's apple-touch-icon, keyed by host; deliberately its own provider, see below
  }, prefix: true
```

Add this comment directly above the enum, since the reason is not obvious from the values:

```ruby
  # website_favicon and website_touch_icon are separate providers for the same
  # host on purpose. Pipeline::Find#unchanged? keys on (provider, provider_id,
  # original_fingerprint, variant), and (provider, provider_id) is unique --
  # so collapsing them would let whichever preset crawled last own the row's
  # original_fingerprint, and the other would short-circuit forever on a
  # fingerprint belonging to a different variant's object.
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler test/models/image_test.rb
```

Expected: PASS. The whole `image_crawler` directory is the guard that two more enum values disturbed nothing — in particular `dedupe_test.rb` and `reuse_rules_test.rb`, whose scopes are keyed on `entry_images`.

- [ ] **Step 5: Commit**

```bash
git add app/models/image.rb test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/processor/cropper_test.rb && git commit -m "Add the host-scoped favicon and touch icon providers

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 2 runs.

---

### Task 2: Conditional requests in the pipeline's downloader

`ImageCrawler::Download` wraps `Down.download` and has no way to send validators or to recognize a 304. Both are needed before `Pipeline::Find` can ask for one.

Two facts verified against the installed gems before this plan was written, so you do not have to rediscover them: `Down.download(url, headers: {...})` accepts arbitrary request headers, and a 304 response raises `Down::ResponseError` whose `response.code` is `"304"` — Down treats every non-2xx as an exception and has no other way to report it.

**Files:**
- Modify: `app/jobs/image_crawler/lib/download.rb`
- Test: `test/jobs/image_crawler/download_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Download.new(url, camo:, minimum_size:, etag: nil, last_modified: nil)` — two new keyword arguments, both defaulting to nil so every existing caller is unaffected.
  - `Download#not_modified? -> Boolean` — true only after a confirmed 304.
  - `Download#response_etag -> String | nil` and `#response_last_modified -> String | nil` — the validators the *response* carried, for storing against the row.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/download_test.rb`:

```ruby
    def test_should_send_conditional_headers_when_given
      url = "http://example.com/favicon.ico"
      request = stub_request(:get, url)
        .with(headers: {"If-None-Match" => "\"abc123\"", "If-Modified-Since" => "Wed, 21 Oct 2026 07:28:00 GMT"})
        .to_return(body: File.new(support_file("image.png")), status: 200, headers: {"Content-Type" => "image/png"})

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"", last_modified: "Wed, 21 Oct 2026 07:28:00 GMT")

      assert_requested request
      assert download.valid?
      refute download.not_modified?
      download.delete!
    end

    def test_should_send_no_conditional_headers_when_not_given
      url = "http://example.com/favicon.ico"
      stub_request(:get, url)
        .to_return(body: File.new(support_file("image.png")), status: 200, headers: {"Content-Type" => "image/png"})

      download = Download.download!(url, minimum_size: nil)

      assert_requested :get, url, headers: {} do |request|
        !request.headers.key?("If-None-Match") && !request.headers.key?("If-Modified-Since")
      end
      download.delete!
    end

    # A 304 is the success case for a conditional request, not a failure. Down
    # raises on every non-2xx, so it arrives as an exception and has to be
    # translated back into an ordinary answer.
    def test_should_treat_304_as_not_modified_rather_than_an_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 304, body: "")

      download = Download.download!(url, minimum_size: nil, etag: "\"abc123\"")

      assert download.not_modified?
      refute download.valid?, "a 304 carries no bytes, so there is nothing valid to process"
    end

    # Only 304. A 404 or a 500 is still a real failure and must not be
    # silently reported as "unchanged", which would make a dead icon look
    # permanently current.
    def test_should_still_raise_for_a_non_304_response_error
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(status: 404, body: "")

      assert_raises Down::ResponseError do
        Download.download!(url, minimum_size: nil, etag: "\"abc123\"")
      end
    end

    def test_should_expose_the_response_validators
      url = "http://example.com/favicon.ico"
      stub_request(:get, url).to_return(
        body: File.new(support_file("image.png")), status: 200,
        headers: {"Content-Type" => "image/png", "ETag" => "\"xyz789\"", "Last-Modified" => "Wed, 21 Oct 2026 07:28:00 GMT"}
      )

      download = Download.download!(url, minimum_size: nil)

      assert_equal "\"xyz789\"", download.response_etag
      assert_equal "Wed, 21 Oct 2026 07:28:00 GMT", download.response_last_modified
      download.delete!
    end
```

If `test/jobs/image_crawler/download_test.rb` does not already exist, create it with this header and put the tests inside:

```ruby
require "test_helper"

module ImageCrawler
  class DownloadTest < ActiveSupport::TestCase
    # tests here
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/download_test.rb
```

Expected: FAIL — `Download#initialize` does not accept `etag:`/`last_modified:` (`ArgumentError: unknown keyword`), and `#not_modified?`, `#response_etag`, `#response_last_modified` do not exist.

- [ ] **Step 3: Add conditional support**

In `app/jobs/image_crawler/lib/download.rb`, replace `initialize` and `download_file`, and add the three readers:

```ruby
    def initialize(url, camo: false, minimum_size: 20_000, etag: nil, last_modified: nil)
      @url = url
      @valid = false
      @minimum_size = minimum_size
      @camo = camo
      @etag = etag
      @last_modified = last_modified
      @not_modified = false
    end
```

```ruby
    def download_file(url)
      url = @camo ? RemoteFile.camo_url(url) : url
      @file = Down.download(url, max_size: 10 * 1024 * 1024, headers: conditional_headers, timeout_options: {read_timeout: 20, write_timeout: 5, connect_timeout: 5})
      @path = @file.path
    rescue Down::ResponseError => exception
      # A 304 is the success case for a conditional request, not an error: the
      # server is confirming the bytes we already hold are current. Down has no
      # other way to say it -- it raises on every non-2xx. Narrow on purpose:
      # a 404 or a 500 must stay an error, or a dead icon would look
      # permanently unchanged and never be re-fetched.
      raise unless exception.response&.code.to_s == "304"
      @not_modified = true
    end

    # Empty for every caller that passes no validators, which is all of them
    # outside the icon family.
    def conditional_headers
      {}.tap do |headers|
        headers["If-None-Match"]     = @etag          if @etag.present?
        headers["If-Modified-Since"] = @last_modified if @last_modified.present?
      end
    end

    def not_modified?
      @not_modified
    end

    # What the response carried, as opposed to what we sent. Stored against the
    # row so the next crawl of this same URL can ask conditionally.
    #
    # "Etag", not "ETag": the configured :http backend (config/initializers/down.rb)
    # canonicalizes header names to Title-Case-Per-Hyphen-Segment (the http gem's
    # HTTP::Headers.canonicalize_name splits on "-"/"_" and capitalizes each
    # segment), and "ETag" has no hyphen to split on, so it comes back "Etag".
    # Verified directly against the installed gems.
    def response_etag
      @file&.headers&.[]("Etag")
    end

    def response_last_modified
      @file&.headers&.[]("Last-Modified")
    end
```

`valid?` is unchanged and already returns false after a 304, because `@file` is nil.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler
```

Expected: PASS. The whole directory is the guard that adding `headers:` to every `Down.download` call — including the ones `Download::Youtube`, `Download::Instagram` and `Download::Vimeo` make through the inherited `download_file` — broke nothing. Those pass no validators, so they send an empty headers hash.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/image_crawler/lib/download.rb test/jobs/image_crawler/download_test.rb && git commit -m "Teach the pipeline downloader to make conditional requests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 5 runs.

---

### Task 3: `Find#attempt_icon` asks conditionally, per URL, and stores what comes back

This is the task the design doc's git archaeology was for. Commit `98c39d3e` ("Favicon finder fix", Nov 2025) commented the validators out of `FaviconCrawler::Finder#download_favicon` and added `break if response.not_modified?` in the same change. Those two facts together explain the bug: `all_favicon_urls` yields several candidates, but the `favicons` row has only **one** `Etag`/`Last-Modified` pair — whichever URL won last time. Sending it to a *different* candidate invites a 304 for content we have never seen, and with the new `break`, one spurious 304 aborted the crawl with `new_favicon = nil` and the favicon simply stopped updating. Disabling the headers was the correct fix for a one-pair-per-host schema.

Per-URL rows dissolve the constraint. In the new model a row **is** a specific source URL (`images.url`), so the validators can only ever be sent back to the URL they came from.

**Files:**
- Modify: `app/models/image.rb` (add `Image.same_fingerprint?`)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`ATTRIBUTES`, `create_image`)
- Modify: `app/jobs/image_crawler/pipeline/find.rb` (`attempt_icon`, `unchanged?`, three new methods)
- Test: `test/models/image_test.rb`, `test/jobs/image_crawler/pipeline/find_test.rb`

**Interfaces:**
- Consumes: `Download#not_modified?`, `#response_etag`, `#response_last_modified` (Task 2).
- Produces:
  - `Image.same_fingerprint?(a, b) -> Boolean` — compares a dashed uuid against a bare hex digest.
  - `ImageCrawler::Image` gains `etag` and `last_modified` attributes, carried Find → Process → Upload and written into the row's `data`.
  - `Find#unchanged?(row)` now takes the loaded row instead of issuing its own query.

**The uuid trap, and why `unchanged?` changes shape.** `unchanged?` currently asks the database (`.where(original_fingerprint: ...).exists?`), which works because Postgres casts a 32-char hex string to `uuid` on the way in. This task needs the row itself (for its `url` and its stored validators), so the comparison moves into Ruby — where it silently breaks, because reading a `uuid` column back gives you a **dashed** 36-character string and every fingerprint we compute is bare hex. `Image.content_storage_path_for` already `.delete("-")`s for exactly this reason. `Image.same_fingerprint?` is that normalization in one named, tested place.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/image_test.rb`:

```ruby
  # A uuid column reads back dashed; every fingerprint we compute is 32 bare
  # hex characters. Comparing them directly is silently always false, which
  # would make every icon look changed on every crawl -- the exact cost
  # content-addressing exists to avoid.
  test "same_fingerprint? compares a dashed uuid against a bare hex digest" do
    bare = Digest::MD5.hexdigest("icon bytes")
    dashed = [bare[0, 8], bare[8, 4], bare[12, 4], bare[16, 4], bare[20, 12]].join("-")

    assert Image.same_fingerprint?(dashed, bare)
    assert Image.same_fingerprint?(bare, dashed)
    assert Image.same_fingerprint?(dashed.upcase, bare)
    refute Image.same_fingerprint?(bare, Digest::MD5.hexdigest("other bytes"))
    refute Image.same_fingerprint?(nil, bare)
    refute Image.same_fingerprint?(bare, "")
  end
```

Append to `test/jobs/image_crawler/pipeline/find_test.rb`, inside the existing test class:

```ruby
      # The validators go back only to the URL they came from. With one pair
      # per host (the favicons table) they could be sent to a candidate we had
      # never fetched, and the resulting 304 aborted the whole crawl -- which
      # is why conditional requests were switched off in 98c39d3e.
      def test_should_send_stored_validators_only_for_the_url_they_came_from
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          stored_url = "http://example.com/stored.ico"
          other_url  = "http://example.com/other.ico"

          ::Image.create!(
            provider: :website_favicon, provider_id: "example.com",
            url: stored_url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png"),
            width: 32, height: 32, bytesize: 400, placeholder_color: "aabbcc",
            data: {"etag" => "\"abc123\"", "last_modified" => "Wed, 21 Oct 2026 07:28:00 GMT"}
          )

          conditional = stub_request(:get, stored_url)
            .with(headers: {"If-None-Match" => "\"abc123\""})
            .to_return(status: 304, body: "")
          unconditional = stub_request(:get, other_url)
            .to_return(body: File.new(support_file("favicon.ico")), status: 200, headers: {"Content-Type" => "image/png"})

          image = Image.new_with_attributes(
            id: "example.com-favicon", preset_name: "favicon",
            image_urls: [other_url, stored_url],
            provider: ::Image.providers[:website_favicon], provider_id: "example.com"
          )
          Find.new.perform(image.to_h)

          assert_requested unconditional
          refute_requested conditional, "the first candidate won, so the stored url was never re-fetched"
        end
      end

      # A 304 now means exactly what the code assumes: this specific source is
      # unchanged. Stop, process nothing, write nothing.
      def test_should_stop_on_a_304_without_processing_or_touching_the_row
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          url = "http://example.com/favicon.ico"
          row = ::Image.create!(
            provider: :website_favicon, provider_id: "example.com",
            url: url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: SecureRandom.hex(16),
            storage_path: ::Image.content_storage_path_for(SecureRandom.hex(16), "32x32", "png"),
            width: 32, height: 32, bytesize: 400, placeholder_color: "aabbcc",
            data: {"etag" => "\"abc123\""},
            updated_at: 1.year.ago
          )
          expected_updated_at = row.updated_at

          stub_request(:get, url).with(headers: {"If-None-Match" => "\"abc123\""}).to_return(status: 304, body: "")

          image = Image.new_with_attributes(
            id: "example.com-favicon", preset_name: "favicon", image_urls: [url],
            provider: ::Image.providers[:website_favicon], provider_id: "example.com"
          )

          assert_no_difference -> { Process.jobs.size } do
            Find.new.perform(image.to_h)
          end
          assert_equal expected_updated_at.to_f, row.reload.updated_at.to_f
        end
      end

      # The bytes are unchanged but the ETag moved -- every static site that
      # rebuilds does this. Store the new validator so the next crawl can get a
      # 304 instead of a download, but do NOT move updated_at: it is a view
      # cache key, and the bytes did not change.
      def test_should_store_new_validators_for_unchanged_bytes_without_moving_updated_at
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          url = "http://example.com/favicon.ico"
          fingerprint = Digest::MD5.file(support_file("favicon.ico")).hexdigest

          row = ::Image.create!(
            provider: :website_favicon, provider_id: "example.com",
            url: url, variant: "32x32",
            image_fingerprint: SecureRandom.hex(16),
            original_fingerprint: fingerprint,
            storage_path: ::Image.content_storage_path_for(fingerprint, "32x32", "png"),
            width: 32, height: 32, bytesize: 400, placeholder_color: "aabbcc",
            data: {"etag" => "\"old\""},
            updated_at: 1.year.ago
          )
          expected_updated_at = row.updated_at

          stub_request(:get, url)
            .to_return(body: File.new(support_file("favicon.ico")), status: 200,
              headers: {"Content-Type" => "image/png", "ETag" => "\"new\""})

          image = Image.new_with_attributes(
            id: "example.com-favicon", preset_name: "favicon", image_urls: [url],
            provider: ::Image.providers[:website_favicon], provider_id: "example.com"
          )

          assert_no_difference -> { Process.jobs.size } do
            Find.new.perform(image.to_h)
          end

          row.reload
          assert_equal "\"new\"", row.data["etag"], "the new validator must be stored or the next crawl re-downloads"
          assert_equal expected_updated_at.to_f, row.updated_at.to_f, "updated_at is a content version, not a row mtime"
        end
      end

      # When the bytes DID change, the validators ride along into the row the
      # pipeline is about to write -- no separate update needed.
      def test_should_carry_the_response_validators_into_the_pipeline
        with_env("R2_BUCKET_IMAGES" => "images-test") do
          url = "http://example.com/favicon.ico"
          stub_request(:get, url)
            .to_return(body: File.new(support_file("favicon.ico")), status: 200,
              headers: {"Content-Type" => "image/png", "ETag" => "\"fresh\"", "Last-Modified" => "Wed, 21 Oct 2026 07:28:00 GMT"})

          image = Image.new_with_attributes(
            id: "example.com-favicon", preset_name: "favicon", image_urls: [url],
            provider: ::Image.providers[:website_favicon], provider_id: "example.com"
          )

          assert_difference -> { Process.jobs.size }, +1 do
            Find.new.perform(image.to_h)
          end

          queued = Process.jobs.last["args"].first
          assert_equal "\"fresh\"", queued["etag"]
          assert_equal "Wed, 21 Oct 2026 07:28:00 GMT", queued["last_modified"]
        end
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler/pipeline/find_test.rb
```

Expected: FAIL — `Image.same_fingerprint?` does not exist; `attempt_icon` sends no conditional headers and has no 304 branch; and `ImageCrawler::Image` drops `etag`/`last_modified` because they are not in `ATTRIBUTES` (`initialize` ignores unknown keys by design), so the queued payload has neither.

- [ ] **Step 3: Add the fingerprint comparison**

In `app/models/image.rb`, add below `content_storage_path_for`:

```ruby
  # A uuid column reads back dashed ("a1b2c3d4-..."); every fingerprint we
  # compute is 32 bare hex characters. Comparing them directly is silently
  # always false, which would make every icon look changed on every crawl --
  # the exact cost content-addressing exists to avoid. The database comparison
  # in a where() clause is safe because Postgres casts on the way in; only
  # Ruby-side comparison needs this.
  def self.same_fingerprint?(one, other)
    return false if one.blank? || other.blank?
    one.to_s.delete("-").casecmp?(other.to_s.delete("-"))
  end
```

- [ ] **Step 4: Carry the validators through the pipeline**

In `app/jobs/image_crawler/lib/image.rb`, add `etag` and `last_modified` to `ATTRIBUTES`. The list is only loosely alphabetical (it already runs `height, width, id` and ends `provider, provider_id, fingerprint, webp_path`), so place them where they read naturally — `etag` after `entry_url`, `last_modified` after `image_urls`. **The names must match the accessors exactly**: `Image#initialize` silently ignores any key not in `ATTRIBUTES`, so a typo here produces no error, just a payload that loses both values between jobs.

and add them to the `data` hash in `create_image`:

```ruby
          data: {
            "legacy_storage_url" => storage_url,
            "preset"             => preset_name,
            "final_url"          => final_url,
            "etag"               => etag,
            "last_modified"      => last_modified
          }.compact
```

`.compact` is new and deliberate: every other preset leaves these nil, and writing explicit nulls into the jsonb would make `row.data["etag"]` present-but-nil rather than absent, which the validator lookup would then send as a header.

- [ ] **Step 5: Ask conditionally and store the answer**

In `app/jobs/image_crawler/pipeline/find.rb`, replace `attempt_icon` and `unchanged?`:

```ruby
      # Icons mutate under a stable URL, so a row for this URL says nothing
      # about the bytes behind it and Dedupe's skip-the-download shortcut is
      # exactly wrong. Always fetch -- but ask conditionally when we can, then
      # short-circuit on the original bytes. Hashing the original rather than
      # the processed output is what lets this skip *processing*, which for a
      # 32x32 render is the expensive part.
      def attempt_icon(original_url)
        row = existing_row

        download = begin
          Download.download!(original_url,
            camo: @image.camo,
            minimum_size: @image.preset.minimum_size,
            **validators_for(row, original_url))
        rescue => exception
          Sidekiq.logger.info @image.trace(message: "download exception", metadata: {exception: exception, original_url: original_url})
          return false
        end

        return false unless download

        # A 304 now means exactly what this assumes: this specific source is
        # unchanged. It could not mean that before -- the favicons row held one
        # validator pair per host, so sending it to a different candidate
        # invited a 304 for content we had never seen, and 98c39d3e switched
        # the headers off rather than act on it.
        if download.not_modified?
          Librato.increment("image.icon_not_modified")
          Sidekiq.logger.info @image.trace(message: "icon not modified", metadata: {original_url: original_url})
          return true
        end

        unless download.valid?
          download.delete!
          # No DownloadCache.failed! here, unlike download_image: icons always
          # fetch, so a URL that consistently serves undecodable bytes is
          # retried every crawl with no backoff -- deliberate.
          Sidekiq.logger.info @image.trace(message: "download invalid", metadata: {original_url: original_url})
          return false
        end

        @image.download_path        = download.persist!
        @image.final_url            = download.image_url
        @image.original_url         = original_url
        @image.original_extension   = download.file_extension
        @image.original_fingerprint = Digest::MD5.file(@image.download_path).hexdigest
        @image.etag                 = download.response_etag
        @image.last_modified        = download.response_last_modified

        if unchanged?(row)
          Librato.increment("image.icon_unchanged")
          Sidekiq.logger.info @image.trace(message: "icon unchanged", metadata: {original_url: original_url})
          store_validators(row, original_url)
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

      def existing_row
        ::Image.find_by(provider: @image.provider, provider_id: @image.provider_id.to_s)
      end

      # Only for the URL the row actually came from. That restriction is the
      # whole reason conditional requests can be switched back on.
      def validators_for(row, original_url)
        return {} unless row && row.url == original_url
        {etag: row.data["etag"], last_modified: row.data["last_modified"]}
      end

      # The bytes are unchanged but the validators may not be -- a static host
      # that rebuilds emits a fresh ETag for identical content. Store them so
      # the next crawl can get a 304 instead of a download.
      #
      # Guarded on row.url == original_url, mirroring validators_for's read
      # side: a different candidate URL can serve byte-identical bytes (a
      # moved <link rel="icon">, an http/https or www variant), and unchanged?
      # only compares variant and fingerprint, never url. Without this guard,
      # that candidate's validators would be written under this row's url --
      # and with If-Modified-Since, a later, fully conformant server could
      # then confirm a false "unchanged" on the next crawl, since the header
      # only promises "304 if not modified since this date". We could instead
      # refresh row.url to the winning candidate, but Image's
      # before_save :fingerprint_url derives url_fingerprint from url and
      # update_column skips callbacks, so that would silently desync the two.
      # Skipping the write is the correct minimal fix -- and the cost is
      # permanent, not a one-time miss: as long as this candidate keeps
      # serving the same bytes as the row, unchanged? keeps short-circuiting
      # before create_image ever runs, so every future crawl of this host
      # downloads this candidate in full rather than getting a 304.
      #
      # update_column, not update: updated_at is a view cache key (Phase B) and
      # must move only when the stored bytes move. That makes images.updated_at
      # a content version rather than a row mtime, which is exactly what the
      # touch rule asks for -- not a compromise of it.
      def store_validators(row, original_url)
        return unless row && row.url == original_url
        merged = row.data.merge("etag" => @image.etag, "last_modified" => @image.last_modified).compact
        return if merged == row.data
        row.update_column(:data, merged)
      end

      # Compared in Ruby rather than SQL because the caller already holds the
      # row (for its url and validators). Image.same_fingerprint? is required,
      # not decorative: original_fingerprint is a uuid column and reads back
      # dashed, while every fingerprint we compute is bare hex.
      def unchanged?(row)
        return false unless row
        return false unless row.variant == @image.variant
        ::Image.same_fingerprint?(row.original_fingerprint, @image.original_fingerprint)
      end
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/image_test.rb test/jobs/image_crawler
```

Expected: PASS, including the pre-existing podcast short-circuit test (`test_should_short_circuit_unchanged_podcast_artwork`), which exercises the same `attempt_icon` path with no validators stored — it is the guard that the new `row`-shaped `unchanged?` still matches when it should.

- [ ] **Step 7: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. 1668 runs (1653 + 2 + 5 + 8), 0 failures, 3 skips. If you see 1 failure with the assertion count unchanged, re-run — see Global Constraints.

- [ ] **Step 8: Commit**

```bash
git add app/models/image.rb app/jobs/image_crawler/lib/image.rb app/jobs/image_crawler/pipeline/find.rb test/models/image_test.rb test/jobs/image_crawler/pipeline/find_test.rb && git commit -m "Ask conditionally for icons, per url, and store what comes back

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 8 runs (2 in `download_test.rb`, 1 in `image_test.rb`, 5 in `find_test.rb`).

---

### Task 4: Split the crawler's candidates by rel, without changing the legacy list

`Finder#all_favicon_urls` fetches the homepage, parses every `<link>` matching `ICON_NAMES`, sorts them (by declared size, then dark-mode-last, then by `ICON_NAMES` position), maps them to absolute URLs, and appends `/favicon.ico`. Apple touch icons are in that list, pooled as interchangeable favicon candidates — the design's change is to route them to their own provider and their own variant, **from the same page fetch**.

Task 5 needs the touch-icon subset. Getting it by calling a second method that re-parses would mean a second homepage fetch, so the parse has to be memoized and both lists derived from it. That is a refactor of a method the legacy path depends on, which is why it is its own task with its own regression test: **`all_favicon_urls` must return exactly what it returns today**, same URLs in the same order.

**Files:**
- Modify: `app/jobs/favicon_crawler/finder.rb`
- Test: `test/jobs/favicon_crawler/finder_test.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Finder#icon_links -> Array<[String, Addressable::URI]>` — memoized `[rel, url]` pairs in the existing sort order. Returns `[]` when the homepage cannot be fetched or parsed.
  - `Finder#all_favicon_urls` — unchanged output; now derived from `icon_links`.
  - `Finder#touch_icon_urls -> Array<Addressable::URI>` — the `apple-touch-icon` / `apple-touch-icon-precomposed` subset, in the same order, with no `/favicon.ico` fallback appended (a host that advertises no touch icon has none).
  - `Finder::TOUCH_ICON_NAMES`.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/favicon_crawler/finder_test.rb`, inside `class FinderTest`:

```ruby
    # The legacy path consumes all_favicon_urls and its ordering is load-
    # bearing: the first candidate that yields a usable image wins. This pins
    # the whole list -- sorted by rel position in ICON_NAMES, then by declared
    # size descending, with /favicon.ico last -- so the refactor that adds
    # touch_icon_urls cannot quietly reorder it.
    test "all_favicon_urls keeps its ordering and its default fallback" do
      body = <<~HTML
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="shortcut icon" href="/shortcut.ico">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal [
        "http://example.com/shortcut.ico",
        "http://example.com/icon-32.png",
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png",
        "http://example.com/favicon.ico"
      ], finder.send(:all_favicon_urls).map(&:to_s)
    end

    test "touch_icon_urls is the apple subset in the same order, with no default fallback" do
      body = <<~HTML
        <html><head>
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="icon" href="/icon-32.png" sizes="32x32">
          <link rel="apple-touch-icon-precomposed" href="/touch-old.png">
        </head></html>
      HTML
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal [
        "http://example.com/touch-180.png",
        "http://example.com/touch-old.png"
      ], finder.send(:touch_icon_urls).map(&:to_s)
    end

    test "touch_icon_urls is empty when the host advertises no touch icon" do
      body = %(<html><head><link rel="icon" href="/icon-32.png"></head></html>)
      stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_empty finder.send(:touch_icon_urls)
    end

    # One page fetch, two lists. Deriving them separately would double the
    # homepage traffic for every crawl.
    test "the homepage is fetched once even when both lists are read" do
      body = %(<html><head><link rel="apple-touch-icon" href="/touch.png"></head></html>)
      request = stub_request(:get, @page_url).to_return(body: body, status: 200)

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))
      finder.send(:all_favicon_urls)
      finder.send(:touch_icon_urls)

      assert_requested request, times: 1
    end

    test "both lists degrade to the default when the homepage cannot be fetched" do
      stub_request(:get, @page_url).to_timeout

      finder = Finder.new
      finder.instance_variable_set(:@favicon, Favicon.new(host: @page_url.host))

      assert_equal ["http://example.com/favicon.ico"], finder.send(:all_favicon_urls).map(&:to_s)
      assert_empty finder.send(:touch_icon_urls)
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/favicon_crawler/finder_test.rb
```

Expected: the `touch_icon_urls` tests FAIL with `NoMethodError`. The `all_favicon_urls` ordering test should **pass already** — it characterizes current behavior, and that is the point: it is the regression guard for Step 3. Say in your report which passed before the change; if the ordering test fails at this step, the expectations are wrong and must be corrected against actual behavior *before* you refactor, or you will refactor toward a wrong target.

- [ ] **Step 3: Derive both lists from one memoized parse**

In `app/jobs/favicon_crawler/finder.rb`, add the constant next to `ICON_NAMES`:

```ruby
    TOUCH_ICON_NAMES = ["apple-touch-icon", "apple-touch-icon-precomposed"]
```

and replace `all_favicon_urls` with these three methods:

```ruby
    # Parsed once and memoized including the failure case: all_favicon_urls and
    # touch_icon_urls both derive from it, and re-deriving would mean a second
    # homepage fetch per crawl. `defined?` rather than ||= so an empty result
    # is not re-attempted.
    def icon_links
      return @icon_links if defined?(@icon_links)
      @icon_links = begin
        homepage = download_homepage
        Nokogiri::HTML5(homepage.to_s).search(xpath)
          .reject {
            it["href"].to_s.strip.empty?
          }
          .sort_by {
            -(it["sizes"] ? it["sizes"].scan(/\d+/).first.to_i : 0)
          }
          .sort_by {
            it["media"] && it["media"].include?("dark") ? 1 : 0
          }
          .sort_by {
            rel = it["rel"].to_s.strip.downcase
            index = ICON_NAMES.index(rel)
            index.nil? ? ICON_NAMES.length : index
          }
          .map {
            [it["rel"].to_s.strip.downcase, Addressable::URI.join(homepage.uri, it["href"])]
          }
      rescue => exception
        Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@favicon.host}"
        []
      end
    end

    def all_favicon_urls
      icon_links.map(&:last).push(default_favicon_location)
    end

    # No default_favicon_location fallback here, unlike all_favicon_urls: every
    # host has a /favicon.ico worth guessing at, and none has a guessable touch
    # icon. A host that advertises none simply has none.
    def touch_icon_urls
      icon_links.filter_map { |rel, url| url if TOUCH_ICON_NAMES.include?(rel) }
    end
```

The sort chain is moved verbatim — same three `sort_by` calls in the same order, same `reject`. Ruby's `sort_by` is not stable, but neither was the original, so this preserves whatever behavior exists rather than improving it. Do not "fix" that here.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/favicon_crawler/finder_test.rb
```

Expected: PASS, **including every pre-existing test in the file untouched**. Those are the real guard — they drive the whole `perform` path and assert on the resulting `Favicon` row, so they prove the legacy behavior survived the refactor. If one fails, `icon_links` is not producing what `all_favicon_urls` produced; fix `icon_links`, not the test.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/favicon_crawler/finder.rb test/jobs/favicon_crawler/finder_test.rb && git commit -m "Separate touch icon candidates from favicon candidates

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 5 runs.

---

### Task 5: Dual-write both presets from the same page fetch

The last step. `FaviconCrawler::Finder` keeps doing everything it does today — the `favicons` row, the base64 column, the S3 object — and additionally hands both candidate lists to the shared pipeline, which produces `images` rows and R2 objects under the two new providers.

**Files:**
- Modify: `app/jobs/favicon_crawler/finder.rb`
- Test: `test/jobs/favicon_crawler/finder_test.rb`

**Interfaces:**
- Consumes: `Finder#all_favicon_urls`, `#touch_icon_urls` (Task 4); `Image.providers[:website_favicon]`, `[:website_touch_icon]` (Task 1); `ImageCrawler::Pipeline::Find` and the `favicon`/`touch_icon` presets (Phase A).
- Produces: `Finder#schedule_pipeline` and `#schedule_icon(preset_name, provider, urls)`.

**Why the schedule sits where it does.** It runs after the candidate loop but **before** `return unless new_favicon.present?`. The pipeline makes its own fetch and its own decisions, so it must not be gated on the legacy path having succeeded. Placing it after the guard would mean a host whose legacy resize failed never accumulates a row — and the legacy resize is exactly the step this migration replaces.

**Why `job_class` stays nil.** The `favicon` and `touch_icon` presets have `job_class: nil`, so `send_to_feedbin` returns early and no callback runs. That is correct and permanent for this family: there is no owner row to write back to (a host is not a record), and cache invalidation will come from putting the image record in the view digest in Phase F — which is the entire point of the design, replacing `TouchFeeds`' 100,000-row fan-out. Do not add a callback job.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/favicon_crawler/finder_test.rb`:

```ruby
    # Dual-store: the legacy favicons row and its S3 object keep being written
    # exactly as before, and the pipeline produces an images row and an R2
    # object alongside. Nothing reads the new rows until a later phase.
    test "schedules both presets from one crawl, keyed by host" do
      body = <<~HTML
        <html><head>
          <link rel="icon" href="/icon-32.png">
          <link rel="apple-touch-icon" href="/touch-180.png">
        </head></html>
      HTML
      stub_request(:any, %r{s3\.amazonaws\.com})
      stub_request(:get, @page_url).to_return(body: body, status: 200)
      stub_request_file("favicon.ico", "http://example.com/icon-32.png")
      stub_request_file("favicon.ico", "http://example.com/touch-180.png")
      stub_request_file("favicon.ico", @default_url)

      assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +2 do
        Finder.new.perform(@page_url.host)
      end

      jobs = ImageCrawler::Pipeline::Find.jobs.last(2).map { _1["args"].first }
      favicon = jobs.find { _1["preset_name"] == "favicon" }
      touch   = jobs.find { _1["preset_name"] == "touch_icon" }

      assert_equal ::Image.providers[:website_favicon], favicon["provider"]
      assert_equal "example.com", favicon["provider_id"]
      assert_includes favicon["image_urls"], "http://example.com/icon-32.png"

      assert_equal ::Image.providers[:website_touch_icon], touch["provider"]
      assert_equal "example.com", touch["provider_id"]
      assert_equal ["http://example.com/touch-180.png"], touch["image_urls"]
    end

    test "schedules only the favicon preset when the host advertises no touch icon" do
      body = %(<html><head><link rel="icon" href="/icon-32.png"></head></html>)
      stub_request(:any, %r{s3\.amazonaws\.com})
      stub_request(:get, @page_url).to_return(body: body, status: 200)
      stub_request_file("favicon.ico", "http://example.com/icon-32.png")
      stub_request_file("favicon.ico", @default_url)

      assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
        Finder.new.perform(@page_url.host)
      end

      assert_equal "favicon", ImageCrawler::Pipeline::Find.jobs.last["args"].first["preset_name"]
    end

    # The pipeline fetches and decides for itself. Gating it on the legacy
    # path having produced a usable image would mean a host whose legacy
    # resize failed never accumulates a row -- and that resize is the step
    # this migration exists to replace.
    test "schedules the pipeline even when the legacy path finds nothing usable" do
      body = %(<html><head><link rel="icon" href="/icon-32.png"></head></html>)
      stub_request(:get, @page_url).to_return(body: body, status: 200)
      stub_request(:get, "http://example.com/icon-32.png").to_return(body: "not an image", status: 200)
      stub_request(:get, @default_url).to_return(status: 404, body: "")

      assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
        Finder.new.perform(@page_url.host)
      end

      assert_nil Favicon.unscoped.find_by(host: @page_url.host)&.url,
        "the legacy path genuinely found nothing, which is the point of this test"
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/favicon_crawler/finder_test.rb
```

Expected: FAIL — no `Pipeline::Find` job is enqueued, so every `assert_difference` reports 0 instead of the expected count.

- [ ] **Step 3: Schedule both presets**

In `app/jobs/favicon_crawler/finder.rb`, insert the call in `update` immediately after the candidate loop and **before** the `return unless new_favicon.present?` guard:

```ruby
      schedule_pipeline

      return unless new_favicon.present?
```

and add the two methods below `update`:

```ruby
    # Dual-store, the shape the entry-preview and podcast migrations both
    # used: everything above keeps writing the favicons row and its S3 object
    # exactly as before, and the shared pipeline produces an images row and an
    # R2 object alongside. Rows accumulate while nothing reads them; the read
    # flips in a later phase, and only then does the legacy store retire.
    #
    # Two schedules rather than one because the presets render at different
    # sizes from different candidate lists -- and they must stay separate
    # providers, since Pipeline::Find#unchanged? keys on (provider,
    # provider_id, original_fingerprint, variant) and a shared provider would
    # let whichever ran last own the fingerprint.
    #
    # This costs a second fetch per crawl: the legacy path downloads, and the
    # pipeline downloads again. Accepted and temporary -- favicon crawls are
    # event-triggered (subscribe, import, save-page, feed-fixer), not a sweep,
    # and it ends when the legacy crawler is retired.
    def schedule_pipeline
      schedule_icon("favicon", ::Image.providers[:website_favicon], all_favicon_urls)
      schedule_icon("touch_icon", ::Image.providers[:website_touch_icon], touch_icon_urls)
    end

    def schedule_icon(preset_name, provider, urls)
      return if urls.empty?

      image = ImageCrawler::Image.new_with_attributes(
        id: "#{@favicon.host}-#{preset_name}",
        preset_name: preset_name,
        image_urls: urls.map(&:to_s),
        provider: provider,
        provider_id: @favicon.host
      )
      ImageCrawler::Pipeline::Find.perform_async(image.to_h)
    end
```

**Both constants must be fully qualified, and this is a real trap rather than style.** `FaviconCrawler::Image` already exists (it is the legacy resizer), so a bare `Image` inside this class resolves to *it*, not to the `Image` model or to `ImageCrawler::Image`. Write `ImageCrawler::Image.new_with_attributes` and `::Image.providers[...]` exactly as above. Getting this wrong fails loudly (`NoMethodError` on `FaviconCrawler::Image`), but only at runtime in a `retry: false` job.

The `id` is only used for log lines here: these presets are `legacy_store: false`, so `image_name` is never built from it, and `job_class` is nil, so it is never parsed back out of a callback payload. A host containing dashes is therefore harmless — unlike the channel ids in Phase D.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/favicon_crawler test/jobs/image_crawler test/models/favicon_test.rb
```

Expected: PASS, including every pre-existing finder test untouched.

- [ ] **Step 5: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. 1676 runs (1653 + 2 + 5 + 8 + 5 + 3), 0 failures, 3 skips.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/favicon_crawler/finder.rb test/jobs/favicon_crawler/finder_test.rb && git commit -m "Dual-write favicons and touch icons through the shared pipeline

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 3 runs.

---

## Manual verification before merge

The suite covers the mechanics. These need eyes.

- [ ] **A real host, end to end.** With a Sidekiq worker running and `R2_BUCKET_IMAGES` set:

```ruby
FaviconCrawler::Finder.perform_async("daringfireball.net", true)
# then
Image.where(provider: [:website_favicon, :website_touch_icon], provider_id: "daringfireball.net")
  .pluck(:provider, :variant, :width, :height, :storage_path, :data)
```

Confirm the favicon row is ≤32×32 with a `.png` storage path, the touch-icon row is ≤200×200, and `data` carries `etag` and/or `last_modified` when the host sends them. Confirm the legacy `Favicon` row and its S3 object are **still written** — dual-store means both, and a missing legacy row would blank favicons for every reader, since nothing reads the new rows yet.

- [ ] **The conditional request actually fires.** Run the same crawl a second time and watch the logs for `icon not modified` (a 304 — the download was skipped entirely) or `icon unchanged` (a 200 whose bytes matched — processing was skipped). Either is success; the first is the better one. Then confirm `updated_at` did not move:

```ruby
Image.find_by(provider: :website_favicon, provider_id: "daringfireball.net").updated_at
```

- [ ] **A host that rebuilds.** Find one whose `ETag` changes without the icon changing (static-site hosts do this on every deploy). Crawl twice and confirm `data["etag"]` moved while `updated_at` did **not**. That is decision 1 working, and it is the one thing in this plan that silently regresses into a cache-invalidation storm if `store_validators` ever stops using `update_column`.

- [ ] **The size change is real and harmless.** The legacy path uses `resize_to_fit(32, 32)`, which upscales a 16×16 source; the new preset uses `resize_to_limit`, which does not. For a host shipping nothing bigger than a 16×16 `favicon.ico`, confirm the new row is 16×16 while the legacy S3 object is still 32×32. Verified safe on paper — `.favicon-wrap .favicon` is pinned to `background-size: 16px 16px` — but this is the first time the two stores visibly disagree, and Phase F is when it reaches the screen.

- [ ] **Nothing changed on screen.** Sign in at `https://feedbin.resolv.app/auto_sign_in` and confirm favicons render exactly as before in the sidebar and the entry list. This phase must be invisible; any visible change means a read flipped that should not have.

## Deployment notes

There is no migration, no cache-key version bump, and no read change — so no cold-cache wave and no user-visible change. What ships is write traffic.

**Expect favicon-related outbound requests to roughly double.** Every favicon crawl now fetches its candidates twice: once for the legacy path, once for the pipeline. Crawls are event-triggered (subscribe, import, save-page, feed-fixer, feed creation) and gated by `updated_recently?`'s one-hour window, so this is not a sweep — but it is the largest single traffic increase in the whole icon migration, and it persists until the legacy crawler retires in Phase F. Conditional requests claw some of it back as rows accumulate validators, but only from the second crawl of a given URL onward.

**Two new Librato counters worth watching:** `image.icon_not_modified` (a 304 — the ideal outcome, and it should climb steadily once rows exist) and `image.icon_unchanged` (a 200 whose bytes matched — the fallback outcome for hosts that send no validators). Both are cross-tenant, not favicon-only: `attempt_icon` increments them for every `content_addressed?` preset, so `podcast`, `podcast_feed`, and `channel_avatar` crawls contribute to the same two counters as `favicon`/`touch_icon`. That matters for the diagnostic here: if `icon_not_modified` stays at zero after rows have accumulated, it does *not* isolate which family's `validators_for` is failing to match — it could mean the conditional half of this work specifically is inert while the three pre-existing tenants are fine, or the reverse. Read it alongside a query scoped to `provider: [:website_favicon, :website_touch_icon]` if you need to know which.

**R2 object growth:** one small PNG per host per variant, and these rows are never garbage collected (see decision 3). The favicon variant is 32×32, so the objects are tiny; the touch-icon variant is up to 200×200.

## What this plan deliberately leaves out

- **Every read.** `FaviconComponent`, `EntriesHelper.entry_favicon`, `ApplicationHelper#favicon_with_host`, `Favicon.for_entries`, and both API v2 endpoints all keep reading the `favicons` table. That is the whole point of a dual-write phase.
- **Touch icons are collected but never consumed.** No component chooses between the two, and no fallback order has to be designed yet. That keeps the blast radius at "favicons look the same as before" while the ≤200×200 rows accumulate. Two consequences the design doc calls out and this plan honors: store whatever a host advertises even when it is small (a 60×60 `apple-touch-icon` yields a 60×60 row at variant `200x200`, since `limit` never upscales), and record real `width`/`height` so a future consumer can filter by size without re-fetching. Expect **no visual signal if touch-icon rendering is wrong** until something displays them — the manual check above is the only feedback available.
- **`favicons.favicon`, the base64 column.** Still written by `Processor#encoded`, still served by `/v2/favicons`. See below.
- **The legacy crawler, its bucket, and the `favicons` table.** All retire in Phase F, after these rows have baked.
- **`Favicon#touch_owners` and `TouchFeeds`** — already deleted in Phase B. Nothing here reinstates them.

## What Phase F must solve

Read this before assuming the retirement is mechanical.

**1. Two public API endpoints read the `favicons` table.** `Api::V2::FaviconsController` uses `Favicon.unscoped` specifically to bypass the default scope that hides the base64 `favicon` column, and `app/views/api/v2/favicons/index.json.jbuilder` emits it. `Api::V2::IconsController` serves `cdn_url` off the same table. Both have tests.

**The base64 column is not being carried forward — decided.** The maintainer's ruling (2026-08-14): `favicons.favicon` is on its way out regardless, so Phase F should not try to reproduce it from an `images` row. Do not read the R2 object back and re-encode it per request. `/v2/favicons` retires with the column; `/v2/icons`, which serves a URL, is the endpoint that needs re-pointing at `Image.r2_url`.

Note this contradicts the design doc, which records "`favicons.favicon` (base64) is dead and ignored" as though nothing served it — a live endpoint does. The conclusion is the same; the reasoning in the design doc is not, so do not cite it as evidence that the endpoint is unused.

**2. The cache digest has to gain the image record.** `EntriesHelper.entries_cache_key` currently digests `entry_favicon(entry, favicons)` — a `Favicon`. When the read flips, that element must become the `images` row, preloaded host-scoped the way `Favicon.for_entries` already is, or the key N+1s on every render. Note the test-suite blind spot the design doc records: `config/environments/test.rb` sets `perform_caching = false`, and Rails skips a collection-cache `cached:` lambda entirely when that is false — so **no controller test can observe a query issued from `entries_cache_key`**. Two N+1s reached review rather than CI in Phase B for exactly this reason.

This is not the only cache digest that reads `favicon`. `FeedsHelper.sidebar_feeds_cache_key` and `.sidebar_tags_cache_key` both digest `feeds.map(&:favicon)` for the sidebar. Both need the `images` row substituted in **and** preloaded, for exactly the same reason and with exactly the same blind spot: `perform_caching = false` in test means no test will catch a regression here either. This is the same shape as the two N+1s referenced above, in a place easy to miss because it is not `EntriesHelper`.

**3. `Favicon#host_class` has no equivalent on `Image`.** `FaviconComponent#icon_favicon` renders `class="favicon #{favicon.host_class}"`, which is `"host-#{host}".parameterize`. An `images` row has `provider_id` (the host) but no such helper. Trivial, but it is a rendering detail that will be missed if the flip is done by pattern-matching on `cdn_url` alone.

**4. `ImportItem` and `Feed` both `has_one :favicon`** keyed on `host`. Both associations, and every `includes(:favicon)` that preloads them, need equivalents or removal.

**5. There is no backfill path — the most important finding of this review.** Every `FaviconCrawler::Finder` trigger is event-driven: `Feed#refresh_favicon` and `Subscription#refresh_favicon` (both `after_create`), `feed_importer.rb` (on import, and again per newly-discovered host), `save_page.rb`, `feed_fixer.rb` (weekly via `lib/clock.rb`, and only for feeds with `fixable_error?`), and the manual refresh in `settings/subscriptions_controller.rb`. `lib/clock.rb` has no favicon sweep of any kind. So `images` rows accumulate in proportion to **new subscription churn**, not to the existing host corpus — a host every current user is already subscribed to, whose feed never errors, will never produce an `images` row no matter how long the bake window runs, because nothing ever re-triggers a crawl for it.

This invalidates the "accumulate, then bake, then flip" sequencing this plan and the design doc both assume: accumulation does not approach full coverage on its own no matter how long it runs. Phase F needs either a one-shot backfill enqueuer over `Favicon.pluck(:host)` (force-crawl, rate-limited so it does not repeat this phase's traffic-doubling all at once) or a read that falls back to the `favicons` row whenever no `images` row exists yet. Either way, Phase F's shape changes from "flip the read" to "flip the read behind a fallback, sweep the backlog, then remove the fallback" — a third phase, not a cleanup step at the end of the second.
