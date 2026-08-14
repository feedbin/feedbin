# Icon Family Phase D — YouTube Channel Avatars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store YouTube channel avatars in the `images` table and R2, keyed by the channel rather than by a URL, so one row serves a channel's own feed and every playlist entry from it — replacing today's arrangement, where the avatar is an 88×88 ggpht URL hotlinked into `feeds.custom_icon` and cached lazily by a proxy on the first viewer's cold miss.

**Architecture:** A new `channel_avatar` preset (200×200 PNG, `unified` + `content_addressed`, `legacy_store: false`) is scheduled from `HarvestEmbeds::Download`, where channel data is already imported on every harvest. It writes an `images` row under a new `embed_icon` provider whose `provider_id` is the YouTube channel id. A new `feeds.channel_id` column, denormalized from the parsed feed, is what lets a feed find that row — and replaces the reverse lookup that reconstructs one exact feed URL string today. `Feed#icon_url` reads the channel row first and falls back to the existing signed proxy, so the transition is per-row and per-feed rather than a global switch.

**Tech Stack:** Rails 8.1, Sidekiq, Fog::Storage (AWS provider; R2 is S3-compatible), libvips via ImageProcessing::Vips, Postgres, Redis, minitest + webmock.

**Design doc:** `docs/superpowers/specs/2026-08-13-icon-family-design.md` — in particular "YouTube channel avatars" and "Resolving the channel: both sides already have the data".

**Predecessors:** `docs/superpowers/plans/2026-08-13-icon-family-foundation.md` (Phases A and B) and `docs/superpowers/plans/2026-08-13-icon-family-phase-c-podcast.md` (Phase C). Everything this plan consumes was built there: `content_addressed?`, `Pipeline::Find#attempt_icon`/`#unchanged?`, `Image.content_storage_path_for`, `Image.r2_url`, `Image.with_storage_lock`, `ImageReplacementCollector`, and `Upload#ensure_stored`.

## Global Constraints

- Prepend `source ~/.bash_profile` to every shell command (ruby version manager).
- Full test suite: `bundle exec rake`. Single file: `bin/rails test <path>`. A single test: `bin/rails test <path> -n <name>`.
- **Baseline for the full suite is 1623 runs, 3948 assertions, 0 failures, 0 errors, 3 skips.** Each task below states how many runs it adds.
- NEVER interpolate values into SQL strings — use hash conditions, binds, or `sanitize_sql_array`.
- **Do not change behavior for any other preset.** `primary`/`twitter`/`youtube` keep 542×304 WebP + jpg. `podcast`/`podcast_feed` keep 200×200 `fill_crop` jpg. `favicon`/`touch_icon` keep 32×32 / 200×200 `icon_crop` png. `icon` (remote_file) keeps `limit_crop`. Their existing tests must stay green **without being edited**.
- **`Image.provider` additions are append-only.** The column stores the integer; renumbering silently repoints every existing row. `embed_icon` is 5. Phase E's `website_favicon` / `website_touch_icon` will be 6 and 7.
- **`Image.entry_images` and `Image.entry_owned` must not change.** Neither scope has anything to do with this phase: a channel-keyed row is owned by no entry and no feed. See "What this plan deliberately leaves out" for what that means for garbage collection.
- **MD5, not SHA1**, for every fingerprint, and always `Digest::MD5.file(path).hexdigest`.
- **The touch rule still governs `images` rows.** A row's `updated_at` may change only when the stored bytes actually change.
- All pipeline jobs remain `retry: false`.
- Commit after each task. Match the repo's terse commit style. End every commit message with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## Three decisions this plan makes that the design doc left open

**The avatar preset must not use `icon_crop`.** The design's per-tenant table says "`200x200` limit, png", and `icon_crop` is exactly that — plus `IconLayer`'s best-layer selection, which rejects any layer whose average colour starts with `ffffff`, and `Cropper#valid?` turns a nil layer into "skip this candidate entirely". For an `.ico` that heuristic means "this layer is padding around the real icon". For a channel avatar it means "a dark logo on a white background", which is the commonest logo there is — verified: a solid-white RGB source makes `Cropper#valid?(false)` return `false` under `icon_crop`. Task 1 adds `limit_png`: the same scale-down-never-up-always-PNG recipe with the layer selection removed.

**`legacy_store: false`.** Podcast artwork dual-stores because `entries.media_image` / `feeds.custom_icon` point at *our* S3 object and blanking them would blank artwork for every reader on the fallback path. YouTube's fallback is different: `custom_icon` holds a **third-party ggpht URL**, rendered through `RemoteFile.signed_url`. That fallback already exists, already works, and costs us no storage — so there is nothing to dual-write. `HarvestEmbeds` keeps writing `custom_icon` exactly as it does today, and it keeps driving `Feed#icon_options`, which is how the design's "`Feed#icon_options` precedence must be preserved" requirement is met.

**`feeds.channel_id` replaces the reverse lookup only, not the WebSub guard.** The design says the column replaces "the two current mechanisms". This plan replaces one of them — `Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=…")` — and deliberately leaves `Feed#youtube_channel_id` and its three callers (`self_url`, `known_hubs`, `update_youtube_videos`) alone. They answer a different question: "is this the canonical channel feed whose self_url and hub we rewrite?", and their strictness (feed_url **and** self_url must both match) is a WebSub guard. Widening it is a change to feed crawling with no icon benefit and a real failure mode, and it belongs in its own change. See "What this plan deliberately leaves out".

---

### Task 1: `limit_png` — scale to fit, always PNG, no layer selection

`Cropper` has four strategies and none of them fits an avatar. `fill_crop` and `smart_crop` crop to an exact frame and upscale a small source. `limit_crop` scales correctly but picks its output format from the source's alpha channel and may hand back the original file untouched — so its format is not a property of the preset, and a content-addressed preset needs one, because `storage_path`'s extension and the R2 `Content-Type` both come from `preset.format`. `icon_crop` is right in every respect except that it runs `IconLayer` first, which rejects mostly-white sources outright.

**Files:**
- Modify: `app/jobs/image_crawler/lib/processor/cropper.rb`
- Test: `test/jobs/image_crawler/processor/cropper_test.rb`

**Interfaces:**
- Consumes: `Processor::Processed.from_pipeline`, `Cropper#source`, `Cropper#save_as`, `Cropper::PNG_SAVER` (all existing).
- Produces: `Cropper#limit_png` — `resize_to_limit(@width, @height)` encoded as PNG, reachable via `crop!` when the preset says `crop: :limit_png`. `Cropper#valid?` is **unchanged**: its `best_layer.nil?` guard is keyed on `@crop == :icon_crop`, so `limit_png` never consults `IconLayer` at all.

**Why this shares an object with `touch_icon`, on purpose.** `channel_avatar` and `touch_icon` are both 200×200 PNG, so identical source bytes content-address to one `storage_path`. That is a dedup win — a creator whose apple-touch-icon and channel avatar are the same export stores one file — and it is only correct while the two recipes agree. They do agree for single-layer sources, because `IconLayer.best` on a one-page image returns that image and both strategies then run the same `resize_to_limit`. The last test below pins that, byte for byte, so Phase E cannot quietly break it.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/processor/cropper_test.rb`, inside `class CropperTest`:

```ruby
      def test_should_scale_down_to_png_without_selecting_a_layer
        file = copy_support_file("image.png")
        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(200, image.width)
        assert_equal(117, image.height)
        assert_equal("png", image.extension)
        assert_equal(:png, ImageFormat.detect(image.file))
        FileUtils.rm image.file
      end

      # limit, not fit: upscaling fabricates no detail, it only makes a bigger
      # file that is equally soft. A channel that has never uploaded anything
      # larger than the 88x88 default thumbnail stays 88x88.
      def test_should_not_upscale_a_small_source
        file = write_solid_png(88, 88, [200, 100, 50])
        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        image = cropper.crop!

        assert_equal(88, image.width)
        assert_equal(88, image.height)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      # icon_crop rejects a mostly-white source outright: IconLayer reads that
      # as an .ico layer that is padding around the real icon, and valid?
      # turns a nil layer into "skip this candidate entirely". For a channel
      # avatar -- a dark logo on a white background is the commonest logo
      # there is -- that would mean never storing one at all.
      def test_should_accept_a_white_source_that_icon_crop_rejects
        file = write_solid_png(300, 300, [255, 255, 255])

        refute Processor::Cropper.new(file, crop: :icon_crop, extension: "png", width: 200, height: 200).valid?(false)

        cropper = Processor::Cropper.new(file, crop: :limit_png, extension: "png", width: 200, height: 200)
        assert cropper.valid?(false)

        image = cropper.crop!
        assert_equal(200, image.width)
        FileUtils.rm image.file
      ensure
        FileUtils.rm_f file
      end

      # channel_avatar and touch_icon are both 200x200 png, so identical source
      # bytes content-address to one shared object. That is deliberate -- one
      # file for a creator whose apple-touch-icon and channel avatar are the
      # same export -- but it is only correct while the two recipes agree on
      # single-layer sources, which is every source either preset sees in
      # practice. If this ever fails, the two presets need distinct storage
      # keys before Phase E ships touch_icon.
      def test_icon_crop_and_limit_png_agree_on_a_single_layer_source
        icon_file  = copy_support_file("image.png")
        limit_file = copy_support_file("image.png")

        icon  = Processor::Cropper.new(icon_file, crop: :icon_crop, extension: "png", width: 200, height: 200).crop!
        limit = Processor::Cropper.new(limit_file, crop: :limit_png, extension: "png", width: 200, height: 200).crop!

        assert_equal icon.fingerprint, limit.fingerprint
        FileUtils.rm icon.file
        FileUtils.rm limit.file
      end

      # Deliberately not private: minitest collects public instance methods,
      # and a `private` section here would silently swallow any test appended
      # after it. Only methods named test_* are run, so a public helper is
      # safe.
      def write_solid_png(width, height, rgb)
        path = File.join(Dir.tmpdir, "#{SecureRandom.hex}.png")
        Vips::Image.black(width, height)
          .linear(1, rgb.first)
          .cast(:uchar)
          .bandjoin(rgb.drop(1))
          .copy(interpretation: :srgb)
          .write_to_file(path)
        path
      end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor/cropper_test.rb
```

Expected: FAIL. `crop!` has no `:limit_png` branch, so it falls through to the default `save_as(geometry, "jpg", JPG_SAVER)` and `geometry` calls `send(:limit_png)` — `NoMethodError: undefined method 'limit_png'`.

- [ ] **Step 3: Add the strategy**

In `app/jobs/image_crawler/lib/processor/cropper.rb`, add the branch to `crop!`:

```ruby
      def crop!
        return limit_crop if @crop == :limit_crop
        return limit_png  if @crop == :limit_png
        return icon_crop  if @crop == :icon_crop
        Processed.from_pipeline(save_as(geometry, "jpg", JPG_SAVER))
      end
```

and add the method directly below `icon_crop`:

```ruby
      # icon_crop without the layer selection: scale the whole source down to
      # fit the box, never up, always PNG.
      #
      # The "always PNG" half is what icon_crop gives us and limit_crop does
      # not -- limit_crop picks png or jpg from the source's alpha channel and
      # may return the original file untouched, so its output format is not a
      # property of the preset. A content-addressed preset needs one, because
      # storage_path's extension and the R2 Content-Type both come from
      # preset.format.
      #
      # The "no layer selection" half is for sources that are one image rather
      # than a container of candidates. A YouTube channel avatar is whatever
      # the creator uploaded; IconLayer's heuristics would reject a perfectly
      # good one for being mostly white, which for an .ico means "padding
      # around the real icon" and for an avatar means "a dark logo on a white
      # background".
      def limit_png
        image = ImageProcessing::Vips
          .source(source)
          .resize_to_limit(@width, @height)

        Processed.from_pipeline(save_as(image, "png", PNG_SAVER))
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/processor
```

Expected: PASS, including `icon_layer_test.rb` and every pre-existing cropper test — nothing about `limit_crop`, `icon_crop`, `fill_crop` or `smart_crop` changed.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/image_crawler/lib/processor/cropper.rb test/jobs/image_crawler/processor/cropper_test.rb && git commit -m "Add a scale-to-fit PNG crop with no layer selection

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 4 runs.

---

### Task 2: Both sides learn their channel

The avatar row is keyed by the channel, so a feed has to know which channel it belongs to in order to find it. Both sides already carry the data and neither stores it usefully.

**Feeds** resolve by reconstructing a URL: `Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=#{id}")`. That depends on one exact spelling — and the model is already inconsistent about which spelling is right, since `Feed#self_url` builds `/xml/feeds/videos.xml` while this lookup and the regex expect `/feeds/videos.xml`.

**Entries** carry `<yt:channelId>` in `entries.data["youtube_channel_id"]` (feedkit's `xml_entry` lists it among the entry attributes), but `provider_metadata` ignores it and sets `provider_parent_id` only when an `Embed` row already exists — leaving it to `HarvestEmbeds` to backfill after an API round trip that returns nothing for a rate-limited key or a video made private.

**Files:**
- Create: `db/migrate/20260814120000_add_channel_id_to_feeds.rb`
- Create: `app/jobs/backfill_feed_channel_ids.rb`
- Modify: `app/models/feed.rb` (callback + two methods, next to `youtube_channel_id`)
- Modify: `app/models/entry.rb:400-405` (`provider_metadata`'s youtube branch)
- Modify: `db/structure.sql` (regenerated by the migration)
- Test: `test/models/feed_test.rb`, `test/jobs/harvest_embeds_test.rb`, `test/jobs/backfill_feed_channel_ids_test.rb` (new)

**Interfaces:**
- Consumes: `feeds.options["youtube_channel_id"]`, refreshed on every crawl by `FeedCrawler::Receiver#perform` (`feed.update(data["feed"].except("feed_url"))`); `entries.data["youtube_channel_id"]`.
- Produces:
  - `feeds.channel_id` — indexed `text` column.
  - `Feed#derived_channel_id -> String | nil` — the parsed value, else the value in `feed_url`.
  - `Feed#channel_id_from_feed_url -> String | nil`.
  - `Feed#set_channel_id` — `before_save` callback assigning the column.
  - `BackfillFeedChannelIds#perform` — one-time, `update_column` so no `updated_at` moves.
  - `Entry#provider_metadata` sets `provider_parent_id` from `data["youtube_channel_id"]`, falling back to the embed lookup.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/feed_test.rb`:

```ruby
  test "channel_id comes from the parsed feed" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "UC-lHJZR3Gqxm24_Vd_AJ5Yw"})
    assert_equal "UC-lHJZR3Gqxm24_Vd_AJ5Yw", feed.channel_id
  end

  test "channel_id falls back to the feed url, and the parsed value wins" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfromurl")
    assert_equal "UCfromurl", feed.channel_id

    feed.update!(options: {"youtube_channel_id" => "UCparsed"})
    assert_equal "UCparsed", feed.reload.channel_id
  end

  test "channel_id is nil for feeds that are not youtube" do
    assert_nil create_feeds(users(:ben)).first.channel_id
  end

  # youtube_channel_id answers a different question and keeps its own,
  # stricter rule: it drives self_url and the WebSub hub, so it requires
  # feed_url and self_url to agree. Icon resolution needs no such guard --
  # today's reverse lookup keys on the feed url alone.
  test "channel_id does not require self_url the way youtube_channel_id does" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")

    assert_nil feed.youtube_channel_id
    assert_equal "UCabc", feed.channel_id
  end
```

Create `test/jobs/backfill_feed_channel_ids_test.rb`:

```ruby
require "test_helper"

class BackfillFeedChannelIdsTest < ActiveSupport::TestCase
  # update_column, not update: channel_id is in no view, and bumping
  # updated_at on every YouTube feed at once would invalidate the sidebar and
  # every entry list referencing them for a change nobody can see.
  test "populates channel_id without moving updated_at" do
    feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCbackfill")
    feed.update_columns(channel_id: nil, updated_at: 1.year.ago)
    before = feed.reload.updated_at

    BackfillFeedChannelIds.new.perform

    feed.reload
    assert_equal "UCbackfill", feed.channel_id
    assert_equal before.to_f, feed.updated_at.to_f
  end

  test "populates channel_id from the parsed options too" do
    feed = Feed.create!(feed_url: "http://example.com/videos.xml", options: {"youtube_channel_id" => "UCparsed"})
    feed.update_column(:channel_id, nil)

    BackfillFeedChannelIds.new.perform

    assert_equal "UCparsed", feed.reload.channel_id
  end

  test "leaves feeds that are not youtube alone" do
    feed = create_feeds(users(:ben)).first

    BackfillFeedChannelIds.new.perform

    assert_nil feed.reload.channel_id
  end
end
```

Append to `test/jobs/harvest_embeds_test.rb`:

```ruby
  # The entry's own <yt:channelId>, which feedkit already parses onto data.
  # Preferring it over the embed lookup means the channel is known the moment
  # the entry is created, rather than after HarvestEmbeds' API round trip --
  # and it keeps working when that round trip comes back empty, which is the
  # ordinary answer for a rate-limited key or a video made private.
  test "should take provider_parent_id from the entry's own channel id" do
    @entry.update(data: {youtube_video_id: "video_id", youtube_channel_id: "UCfromentry"}, provider_id: "video_id")
    @entry.provider_youtube!
    @entry.send(:provider_metadata)
    @entry.save!

    assert_equal("UCfromentry", @entry.reload.provider_parent_id)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/jobs/backfill_feed_channel_ids_test.rb test/jobs/harvest_embeds_test.rb
```

Expected: FAIL. `feeds` has no `channel_id` column (`NoMethodError`/`ActiveModel::UnknownAttributeError`), `BackfillFeedChannelIds` is not defined, and `provider_metadata` still reads only the embed table so `provider_parent_id` comes back nil.

- [ ] **Step 3: Add the column**

Create `db/migrate/20260814120000_add_channel_id_to_feeds.rb`:

```ruby
class AddChannelIdToFeeds < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :feeds, :channel_id, :text
    add_index :feeds, :channel_id, algorithm: :concurrently
  end
end
```

Run it — this also regenerates `db/structure.sql`, which is committed:

```bash
source ~/.bash_profile && bin/rails db:migrate && bin/rails db:test:prepare
```

- [ ] **Step 4: Derive it on the feed**

In `app/models/feed.rb`, add the callback next to the existing `before_save :set_hubs` (line 19):

```ruby
  before_save :set_channel_id
```

and add these three methods directly above `youtube_channel_id` (line 232), which stays exactly as it is:

```ruby
  # Which YouTube channel this feed's videos come from, denormalized so a
  # channel avatar harvested once can find the feeds that render it without
  # reconstructing a url string.
  #
  # Deliberately wider than youtube_channel_id below, which answers a
  # different question -- "is this the canonical channel feed whose self_url
  # and hub we rewrite?" -- and requires feed_url and self_url to agree. That
  # is the right guard for WebSub and the wrong one for icon resolution,
  # where the feed url alone is exactly what the reverse lookup this replaces
  # already keys on.
  def derived_channel_id
    options.safe_dig("youtube_channel_id").presence || channel_id_from_feed_url
  end

  # The parsed <yt:channelId> wins when both exist. This is the fallback for a
  # feed that has not been crawled since feedkit started surfacing it, and for
  # a brand-new feed that has not been parsed at all yet.
  def channel_id_from_feed_url
    return nil if feed_url.blank?
    match = feed_url.match(%r{\Ahttps?://(?:www\.)?youtube\.com/feeds/videos\.xml\?channel_id=([^#?&]+)})
    match && match[1]
  end

  def set_channel_id
    self[:channel_id] = derived_channel_id
  end
```

- [ ] **Step 5: Backfill the feeds that already exist**

Create `app/jobs/backfill_feed_channel_ids.rb`:

```ruby
# One-time: populates feeds.channel_id for feeds that already exist. New and
# re-crawled feeds get it from Feed#set_channel_id, but a feed that is not
# crawled again for hours would render no channel avatar until it was, and the
# harvest that stores the avatar does not wait for that.
#
# update_column, not update: channel_id is part of no view, and bumping
# updated_at on every YouTube feed at once would invalidate the sidebar and
# every entry list referencing them for a change nobody can see.
class BackfillFeedChannelIds
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform
    candidates.find_each do |feed|
      value = feed.derived_channel_id
      next if value.blank?
      feed.update_column(:channel_id, value)
    end
  end

  # Both sources the derivation reads, so the scan does not have to visit
  # every feed row. Bound conditions, never interpolation -- the LIKE pattern
  # contains a "?" of its own.
  def candidates
    from_url    = Feed.where("feed_url LIKE ?", "%youtube.com/feeds/videos.xml?channel_id=%")
    from_parsed = Feed.where("options->>'youtube_channel_id' IS NOT NULL")
    from_url.or(from_parsed).where(channel_id: nil)
  end
end
```

- [ ] **Step 6: Set the entry's channel at creation**

In `app/models/entry.rb`, replace the `youtube?` branch of `provider_metadata` (lines 400-405):

```ruby
    elsif youtube?
      self.provider = self.class.providers[:youtube]
      self.provider_id = data["youtube_video_id"]
      # The entry's own <yt:channelId>, which feedkit already parses onto
      # data, in preference to the embed lookup. That makes the channel known
      # the moment the entry is created rather than after HarvestEmbeds' API
      # round trip -- and it keeps working when that round trip returns
      # nothing, which is the ordinary answer for a rate-limited key or a
      # video that has been made private. A playlist feed whose videos come
      # from many channels gets each entry's real channel from the XML alone.
      self.provider_parent_id = data["youtube_channel_id"].presence ||
        Embed.youtube_video.find_by_provider_id(self.provider_id)&.parent_id
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/jobs/backfill_feed_channel_ids_test.rb test/jobs/harvest_embeds_test.rb test/jobs/feed_crawler
```

Expected: PASS. `harvest_embeds_test.rb`'s pre-existing `"should add provider_parent_id from existing embed"` proves the embed fallback still fires when the entry carries no channel id of its own; `test/jobs/feed_crawler` proves the new `before_save` did not disturb parsing or receiving.

- [ ] **Step 8: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. 1635 runs (baseline 1623 + 4 from Task 1 + 8 here), 0 failures, 3 skips.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260814120000_add_channel_id_to_feeds.rb db/structure.sql app/models/feed.rb app/models/entry.rb app/jobs/backfill_feed_channel_ids.rb test/models/feed_test.rb test/jobs/backfill_feed_channel_ids_test.rb test/jobs/harvest_embeds_test.rb && git commit -m "Denormalize the YouTube channel onto feeds and entries

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 8 runs.

---

### Task 3: The `embed_icon` provider, the `channel_avatar` preset, and `ChannelImage`

The storage side. After this the pipeline can store an avatar; nothing schedules one yet (Task 4) and nothing reads one yet (Task 5).

**Files:**
- Modify: `app/models/image.rb` (enum)
- Modify: `app/jobs/image_crawler/lib/image.rb` (`PRESETS`)
- Create: `app/jobs/image_crawler/channel_image.rb`
- Test: `test/jobs/image_crawler/image_test.rb`, `test/jobs/image_crawler/channel_image_test.rb` (new)

**Interfaces:**
- Consumes: `Cropper#limit_png` (Task 1); `feeds.channel_id` (Task 2); `content_addressed?`, `legacy_store?`, `unified?`, `Image#storage_path`, `Pipeline::Find#attempt_icon` (Phases A–C).
- Produces:
  - `Image.providers[:embed_icon] == 5`, with the `provider_embed_icon` scope Rails generates from the `prefix: true` enum.
  - `PRESETS[:channel_avatar]` — `width: 200, height: 200, minimum_size: nil, crop: :limit_png, format: "png", validate: false, unified: true, content_addressed: true, legacy_store: false, job_class: ChannelImage`.
  - `ImageCrawler::ChannelImage.schedule(embed)` — takes a `youtube_channel` `Embed`, enqueues `Pipeline::Find`.
  - `ImageCrawler::ChannelImage#perform(id, image)` — the pipeline callback; touches the feeds for the channel when something was actually stored.

**Why `validate: false`.** `Cropper#valid?(true)` requires `source.width >= @width && source.height >= @height`. A channel that has never uploaded anything past the 88×88 default would be rejected at 200×200. `limit` never upscales, so storing the 88×88 as-is is strictly better than storing nothing — and `width`/`height` are recorded on the row, so a future consumer can filter by size without re-fetching.

**Why the job id uses `delete_suffix`.** `send_to_feedbin` passes only `(id, payload)`, so the callback has to recover the channel id from the id. The other tenants do `id.split("-").first`, which is wrong here: a YouTube channel id is base64url, so `-` and `_` are ordinary characters in it and `UC-lHJZR3Gqxm24_Vd_AJ5Yw-channel` would come back as `UC`. Stripping a fixed suffix is separator-agnostic.

- [ ] **Step 1: Write the failing tests**

Append to `test/jobs/image_crawler/image_test.rb`, inside `class ImageTest`:

```ruby
    # Content-addressed and R2-only. Unlike podcast artwork there is no legacy
    # object to dual-write: the fallback read path is a third-party ggpht url
    # rendered through the signing proxy, which costs us no storage.
    test "channel_avatar is content-addressed, R2-only, and keyed by the bytes" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      image = Image.new_with_attributes(
        id: "UCabc-channel", preset_name: "channel_avatar", image_urls: [],
        provider: ::Image.providers[:embed_icon], provider_id: "UCabc",
        original_url: "https://yt3.ggpht.com/avatar.jpg", original_fingerprint: fingerprint
      )

      assert image.content_addressed?
      refute image.legacy_store?, "there is no legacy object for this tenant"
      assert_equal "200x200", image.variant
      assert_equal "png", image.preset.format
      assert_equal :limit_png, image.preset.crop
      assert_equal ::Image.content_storage_path_for(fingerprint, "200x200", "png"), image.storage_path
    end

    # Not a collision: the two presets render the same recipe at the same size
    # in the same format, so identical source bytes are meant to share one
    # stored object. cropper_test pins the recipes byte-for-byte.
    test "channel_avatar and touch_icon share an object for identical bytes" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      build = ->(preset, provider) {
        Image.new_with_attributes(
          id: "a", preset_name: preset, image_urls: [],
          provider: ::Image.providers[provider], provider_id: "UCabc",
          original_url: "https://yt3.ggpht.com/avatar.jpg", original_fingerprint: fingerprint
        )
      }

      assert_equal build.call("touch_icon", :feed_icon).storage_path,
        build.call("channel_avatar", :embed_icon).storage_path
    end

    # Same size, different format. podcast is jpg and the extension is the
    # only thing keeping the two object keys apart.
    test "channel_avatar does not collide with podcast at the same variant" do
      fingerprint = Digest::MD5.hexdigest("avatar bytes")
      avatar = Image.new_with_attributes(
        id: "a", preset_name: "channel_avatar", image_urls: [],
        provider: ::Image.providers[:embed_icon], provider_id: "UCabc",
        original_url: "https://example.com/a.jpg", original_fingerprint: fingerprint
      )
      podcast = Image.new_with_attributes(
        id: "b", preset_name: "podcast", image_urls: [],
        provider: ::Image.providers[:entry_icon], provider_id: 1,
        original_url: "https://example.com/a.jpg", original_fingerprint: fingerprint
      )

      refute_equal avatar.storage_path, podcast.storage_path
    end
```

Create `test/jobs/image_crawler/channel_image_test.rb`:

```ruby
require "test_helper"

module ImageCrawler
  class ChannelImageTest < ActiveSupport::TestCase
    setup do
      flush_redis
    end

    def channel(thumbnails)
      Embed.youtube_channel.create!(
        provider_id: "UCabc",
        data: {"snippet" => {"thumbnails" => thumbnails}}
      )
    end

    # The channels API returns default (88x88), medium (240x240) and high
    # (800x800). Today's code takes default and hotlinks it, which is soft in
    # every slot bigger than a favicon.
    test "schedules a Find job for the largest thumbnail" do
      record = channel({
        "default" => {"url" => "https://yt3.ggpht.com/small.jpg"},
        "medium"  => {"url" => "https://yt3.ggpht.com/medium.jpg"},
        "high"    => {"url" => "https://yt3.ggpht.com/large.jpg"}
      })

      assert_difference -> { Pipeline::Find.jobs.size }, +1 do
        ChannelImage.schedule(record)
      end

      args = Pipeline::Find.jobs.last["args"].first
      assert_equal ["https://yt3.ggpht.com/large.jpg"], args["image_urls"]
      assert_equal "channel_avatar", args["preset_name"]
      assert_equal ::Image.providers[:embed_icon], args["provider"]
      assert_equal "UCabc", args["provider_id"]
      assert_equal "UCabc-channel", args["id"]
      assert_nil args["feed_id"], "the row belongs to the channel, not to any one feed"
    end

    test "falls back down the thumbnail ladder" do
      ChannelImage.schedule(channel({"default" => {"url" => "https://yt3.ggpht.com/small.jpg"}}))

      assert_equal ["https://yt3.ggpht.com/small.jpg"],
        Pipeline::Find.jobs.last["args"].first["image_urls"]
    end

    test "schedules nothing when the channel advertises no thumbnail" do
      record = Embed.youtube_channel.create!(provider_id: "UCabc", data: {})

      assert_no_difference -> { Pipeline::Find.jobs.size } do
        ChannelImage.schedule(record)
      end
    end

    # The sidebar's key and entries_cache_key both include the feed, not the
    # icon row, so a feed rendering this channel has to be touched or it keeps
    # serving the old avatar.
    test "touches every feed for the channel when the avatar was stored" do
      one = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      two = Feed.create!(feed_url: "https://youtube.com/feeds/videos.xml?channel_id=UCabc")
      [one, two].each { _1.update_column(:updated_at, 1.year.ago) }
      before = one.reload.updated_at

      ChannelImage.new.perform("UCabc-channel", {"storage_path" => "abc/abc123.png"})

      assert_operator one.reload.updated_at, :>, before
      assert_operator two.reload.updated_at, :>, before
    end

    # Channel ids are base64url: "-" and "_" are ordinary characters in them,
    # so the split("-").first idiom the other tenants use would truncate this
    # one to "UC" and touch nothing.
    test "recovers a channel id containing a dash from the job id" do
      channel_id = "UC-lHJZR3Gqxm24_Vd_AJ5Yw"
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}")
      feed.update_column(:updated_at, 1.year.ago)
      before = feed.reload.updated_at

      ChannelImage.new.perform("#{channel_id}-channel", {"storage_path" => "abc/abc123.png"})

      assert_operator feed.reload.updated_at, :>, before
    end

    # storage_path is absent when the R2 write failed and Upload degraded to
    # legacy -- and this preset has no legacy object. Nothing was stored, so
    # there is nothing to invalidate.
    test "touches nothing when nothing was stored" do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      feed.update_column(:updated_at, 1.year.ago)
      before = feed.reload.updated_at

      ChannelImage.new.perform("UCabc-channel", {"processed_url" => "https://cdn.example.com/a.png"})

      assert_equal before.to_f, feed.reload.updated_at.to_f
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/channel_image_test.rb
```

Expected: FAIL — `Image.providers` has no `:embed_icon` key (so `::Image.providers[:embed_icon]` is nil), `PRESETS` has no `:channel_avatar`, and `ImageCrawler::ChannelImage` does not exist.

- [ ] **Step 3: Add the provider**

In `app/models/image.rb`, append to the enum. **Append-only — never renumber**, the column stores the integer:

```ruby
  enum :provider, {
    entry_icon:         0,     # entry specific icon (microposts with avatar, twitter, podcasts, youtube)
    entry_link_preview: 1,     # link preview image
    entry_preview:      2,     # main preview image
    feed_icon:          3,     # feed-level icon (mastodon, podcast, youtube, twitter)
    remote_file:        4,     # adhoc images
    embed_icon:         5,     # embed-provider icon keyed by that provider's own id (YouTube channel avatars)
  }, prefix: true
```

- [ ] **Step 4: Add the callback job**

This comes **before** the preset on purpose. `PRESETS` names `ChannelImage` as a bare constant evaluated when `ImageCrawler::Image` loads, so adding the preset first leaves the app unable to boot until this file exists.

Create `app/jobs/image_crawler/channel_image.rb`:

```ruby
module ImageCrawler
  class ChannelImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-channel".freeze

    # Largest first. The channels API returns default (88x88), medium
    # (240x240) and high (800x800); the avatar is hotlinked from default
    # today, which is soft in every slot bigger than a favicon.
    THUMBNAIL_SIZES = %w[high medium default].freeze

    # Scoped to the channel, not to a feed and not to an entry: one row serves
    # the channel's own feed and every playlist entry from that channel, which
    # is the case that motivated splitting feed-level from entry-level in the
    # first place. feed_id is left nil for the same reason -- a channel has no
    # single feed, and feed_id only feeds ReuseRules, which a content-addressed
    # preset never reaches.
    def self.schedule(channel)
      url = THUMBNAIL_SIZES.filter_map { channel.data.safe_dig("snippet", "thumbnails", it, "url") }.first
      return if url.blank?

      image = Image.new_with_attributes(
        id: "#{channel.provider_id}#{SUFFIX}",
        preset_name: "channel_avatar",
        image_urls: [url],
        provider: ::Image.providers[:embed_icon],
        provider_id: channel.provider_id
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    # Nothing is written onto a feed: the row is keyed by the channel and
    # Feed#icon_url reads it. What is left is cache invalidation -- the
    # sidebar's key and entries_cache_key both include the feed, not the icon
    # row, so a feed rendering this channel keeps serving the old avatar
    # unless it is touched. Bounded by design (a channel has one feed,
    # occasionally a few url spellings of it), which is why this is a touch
    # rather than a digest change; the fan-out this design exists to kill is
    # the 100,000-row medium.com favicon case, not this.
    #
    # Only reached when the bytes actually changed: Pipeline::Find's
    # unchanged? short circuit returns before Process for a re-crawl of the
    # same avatar, so an unchanged channel costs no invalidation.
    def perform(id, image)
      return if image["storage_path"].blank?

      # delete_suffix, not split("-").first as the other tenants do: a
      # YouTube channel id is base64url, so "-" and "_" are ordinary
      # characters in it and UC-lHJZR3Gqxm24_Vd_AJ5Yw would come back as "UC".
      Feed.where(channel_id: id.delete_suffix(SUFFIX)).find_each(&:touch)
    end
  end
end
```

- [ ] **Step 5: Add the preset**

In `app/jobs/image_crawler/lib/image.rb`, add to `PRESETS` directly after `podcast_feed`:

```ruby
      channel_avatar: {
        width: 200,
        height: 200,
        minimum_size: nil,
        crop: :limit_png,
        format: "png",
        validate: false,
        unified: true,
        content_addressed: true,
        legacy_store: false,
        job_class: ChannelImage
      },
```

`legacy_store: false` is load-bearing, not decorative: `legacy_store?` is `preset.legacy_store != false`, so omitting the key would turn the S3 write **on**. It is the opposite call from podcast, and for a reason — this tenant's fallback read path is a third-party ggpht url served through `RemoteFile.signed_url`, not an S3 object of ours, so there is nothing to dual-write. `validate: false` because an 88×88 source is smaller than the 200×200 box and `limit` never upscales — storing it as-is beats storing nothing.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/image_crawler test/models/image_test.rb
```

Expected: PASS. The whole `image_crawler` directory is the guard that the new enum value and the new preset disturbed no existing preset — in particular `dedupe_test.rb` and `reuse_rules_test.rb`, whose scopes are keyed on `entry_images` and must be unaffected by a sixth provider.

- [ ] **Step 7: Commit**

```bash
git add app/models/image.rb app/jobs/image_crawler/lib/image.rb app/jobs/image_crawler/channel_image.rb test/jobs/image_crawler/image_test.rb test/jobs/image_crawler/channel_image_test.rb && git commit -m "Store YouTube channel avatars keyed by the channel

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 9 runs.

---

### Task 4: Harvest the avatar instead of hotlinking it

`HarvestEmbeds::Download#update_related_records` is where channel data lands, and `Embed.import(on_duplicate_key_update: {columns: [:data]})` already refreshes it every time any video from that channel is harvested. That is the existing cadence the design says to reuse — no new scheduler.

The same loop carries a live bug. `channels = videos.map(&:parent).uniq` puts a `nil` in the list whenever a video embed exists but its channel embed does not, which is the ordinary result when the videos half of the API succeeded and the channels half came back empty (quota trip, or every channel in the batch terminated). `nil.provider_id` then kills this `retry: false` job. Fixing it is a prerequisite for scheduling anything inside that loop.

**Files:**
- Modify: `app/jobs/harvest_embeds.rb:89-98`
- Test: `test/jobs/harvest_embeds_test.rb`

**Interfaces:**
- Consumes: `ImageCrawler::ChannelImage.schedule` (Task 3); `feeds.channel_id` (Task 2).
- Produces: nothing new. `update_related_records` keeps its signature and keeps writing `feeds.custom_icon` from `thumbnails.default.url` exactly as today.

**Why `custom_icon` keeps the 88×88 `default` url.** It is now only the fallback for a feed whose row has not landed yet. Pointing it at `high` instead would change every YouTube feed's `custom_icon` on the next harvest — a `CacheRemoteFile` download and a cache invalidation per feed — to improve a path that the row is about to replace. Not worth it.

- [ ] **Step 1: Write the failing tests**

In `test/jobs/harvest_embeds_test.rb`, first give `stub_youtube_api` a large thumbnail and stub it. The `default` entry stays, so the pre-existing `assert_equal("image_url", @feed.reload.custom_icon)` is unaffected — but the stub is required, because `"should create embed records"` runs under `Sidekiq::Testing.inline!` and would otherwise reach a real download. `WebMock::NetConnectNotAllowedError` descends from `Exception`, not `StandardError`, so `Pipeline::Find`'s `rescue => exception` would not catch it and the test would error.

```ruby
    channels = {
      items: [
        {
          id: "channel_id",
          snippet: {
            thumbnails: {
              default: {
                url: "image_url"
              },
              high: {
                url: "https://yt3.ggpht.com/avatar.jpg"
              }
            }
          },
        }
      ]
    }
    stub_request(:get, %r{www.googleapis.com/youtube/v3/channels})
      .to_return body: channels.to_json, headers: {content_type: "application/json"}

    stub_request_file("image.png", "https://yt3.ggpht.com/avatar.jpg", headers: {content_type: "image/png"})
```

Then append these tests:

```ruby
  test "schedules the channel avatar from the largest thumbnail" do
    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") }
    stub_youtube_api

    HarvestEmbeds.new.perform(nil, true)
    job = HarvestEmbeds::Download.jobs.shift

    assert_difference -> { ImageCrawler::Pipeline::Find.jobs.size }, +1 do
      HarvestEmbeds::Download.new.perform(*job["args"])
    end

    args = ImageCrawler::Pipeline::Find.jobs.last["args"].first
    assert_equal ["https://yt3.ggpht.com/avatar.jpg"], args["image_urls"]
    assert_equal "channel_avatar", args["preset_name"]
    assert_equal "channel_id", args["provider_id"]
  end

  # The old lookup reconstructed one exact url string, so a feed subscribed
  # through any other spelling of the same channel never got its icon.
  test "updates every feed for the channel, not just the canonical url" do
    other = Feed.create!(feed_url: "https://youtube.com/feeds/videos.xml?channel_id=channel_id")

    @entry.update(data: {youtube_video_id: "video_id"}, provider_id: "video_id")
    @entry.provider_youtube!
    Sidekiq.redis { _1.sadd(HarvestEmbeds::SET_NAME, "video_id") }
    stub_youtube_api

    HarvestEmbeds.new.perform(nil, true)
    job = HarvestEmbeds::Download.jobs.shift
    HarvestEmbeds::Download.new.perform(*job["args"])

    assert_equal "image_url", @feed.reload.custom_icon
    assert_equal "image_url", other.reload.custom_icon
  end

  # The channels half of the API can come back empty while the videos half
  # succeeded -- a quota trip, or every channel in the batch terminated. The
  # video embeds still import, so their parent lookup finds nothing and puts a
  # nil in the channels list, which killed this retry: false job on
  # nil.provider_id.
  test "survives videos whose channel embed was never imported" do
    Embed.youtube_video.create!(provider_id: "video_id", parent_id: "channel_id", data: {})

    assert_nothing_raised do
      HarvestEmbeds::Download.new.update_related_records(["video_id"])
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/jobs/harvest_embeds_test.rb
```

Expected: FAIL — no `Pipeline::Find` job is enqueued, `other` keeps a nil `custom_icon` because the lookup still matches one exact url, and the nil-parent case raises `NoMethodError: undefined method 'provider_id' for nil`.

- [ ] **Step 3: Rewrite the loop**

In `app/jobs/harvest_embeds.rb`, replace the first half of `update_related_records`:

```ruby
    def update_related_records(ids)
      videos    = Embed.youtube_video.where(provider_id: ids).includes(:parent)
      # filter_map, not map: parent is a lookup by provider_id, and the
      # channels half of the API can come back empty (quota, terminated
      # channels) while the videos half succeeded. A nil in here reached
      # channel.provider_id and killed this retry: false job.
      channels  = videos.filter_map(&:parent).uniq
      video_map = videos.index_by(&:provider_id)

      channels.each do |channel|
        # Scheduled for every harvested channel, feed or no feed: the row is
        # keyed by the channel, so a playlist entry from a channel nobody
        # subscribes to directly resolves through the same row.
        ImageCrawler::ChannelImage.schedule(channel)

        # where, not find_by: the same channel can own more than one feed row
        # (http/https, with and without www), and the url this replaced could
        # only ever match one exact spelling. custom_icon keeps the 88x88
        # default thumbnail -- it is now only the fallback for a feed whose
        # images row has not landed yet, and repointing it at the large
        # thumbnail would cost a re-proxy and a cache invalidation per feed to
        # improve a path the row is about to replace.
        Feed.where(channel_id: channel.provider_id).find_each do |feed|
          feed.update(custom_icon: channel.data.safe_dig("snippet", "thumbnails", "default", "url"))
        end
      end
```

The rest of the method — the `Entry.provider_youtube` loop and `requeue_live_videos(videos)` — is unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/jobs/harvest_embeds_test.rb test/models/embed_test.rb
```

Expected: PASS, including the pre-existing `"should create embed records"`, which now runs the whole pipeline inline: `Find` downloads the stubbed PNG, `Process` crops it through `limit_png`, and `Upload` finds `unified?` false (no `R2_BUCKET_IMAGES` in the test env) and `legacy_store?` false, so it stores nothing and hands `ChannelImage` a payload with no `storage_path`.

- [ ] **Step 5: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. 1647 runs (Task 3 added 9, this one 3), 0 failures, 3 skips.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/harvest_embeds.rb test/jobs/harvest_embeds_test.rb && git commit -m "Harvest channel avatars through the pipeline instead of hotlinking

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 3 runs.

---

### Task 5: Feeds render the stored avatar

The rows exist; nothing reads them. `Feed#icon_url` still resolves to `RemoteFile.signed_url(icon)`, the signed proxy that serves a cold miss straight from Google for the first viewer of any channel.

**Files:**
- Modify: `app/models/feed.rb` (association, `icon_url`)
- Modify: 13 files carrying 16 preload sites (listed in Step 4)
- Test: `test/models/feed_test.rb`, `test/components/favicon_component_test.rb`, `test/views/query_count_test.rb`

**Interfaces:**
- Consumes: `Image.r2_url` (Phase C); `feeds.channel_id` (Task 2); `provider: embed_icon` rows (Tasks 3–4).
- Produces:
  - `Feed#channel_image_record` — `has_one`, scoped `provider_embed_icon`, joining `images.provider_id` to `feeds.channel_id`.
  - `Feed#icon_url` gains a middle branch. `Feed#icon`, `#icon_options`, `#default_icon_format` and `FaviconComponent` are all **unchanged**.

**Why the feed's own row wins.** `icon_image_record` is `feed_icon` keyed on the feed's own id — artwork that belongs to this feed and nothing else. `channel_image_record` is shared across every feed for the channel. More specific first. In practice a feed is never both a podcast and a YouTube channel, so the ordering is a tie-break that should never be exercised; it is written down so it is not decided by accident later.

**Why no `default_icon_format` change.** A feed with a channel row but no `custom_icon` renders `class="icon-format-"` — reachable now, because a new subscription to a channel someone else already harvested finds the shared row before its own first harvest writes `custom_icon`. That is cosmetically correct as written: `application.scss:1534` styles `.twitter-profile-image` round and only `.icon-format-square` overrides it, so an empty suffix renders round, which is what a channel avatar should be.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/feed_test.rb`:

```ruby
  test "icon_url prefers the channel row over the signed proxy" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      feed.update!(custom_icon: "https://yt3.ggpht.com/small.jpg")

      assert_match "/files/icons/", feed.icon_url, "the legacy path is proxied through a signed url"

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png")
      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Feed.find(feed.id).icon_url
    end
  end

  # One row serves every feed for the channel -- that is the whole point of
  # keying on the channel rather than on the feed.
  test "every feed for a channel resolves the same avatar row" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      one = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      two = Feed.create!(feed_url: "https://youtube.com/feeds/videos.xml?channel_id=UCabc")

      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png")
      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{path}", Feed.find(one.id).icon_url
      assert_equal "https://images.example.com/#{path}", Feed.find(two.id).icon_url
    end
  end

  # A tie that should never happen -- no feed is both a podcast and a YouTube
  # channel -- written down so it is not decided by accident later.
  test "the feed's own icon row outranks the shared channel row" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")

      own = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "jpg")
      Image.create!(
        provider: :feed_icon, provider_id: feed.id.to_s, feed_id: feed.id,
        url: "http://example.com/show.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: own,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )
      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      assert_equal "https://images.example.com/#{own}", Feed.find(feed.id).icon_url
    end
  end
```

Append to `test/components/favicon_component_test.rb`:

```ruby
  # The stored avatar is already on our own CDN. Wrapping it in the signing
  # proxy would send a request we control back through a redirector built for
  # third-party urls.
  test "channel avatar from the stored row is served directly, not through the proxy" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      path = Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png")
      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: path,
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(feed.id))

      assert_includes output.to_s, "https://images.example.com/#{path}"
      refute_includes output.to_s, "/files/icons/"
    end
  end

  # A new subscription to a channel someone else already harvested finds the
  # shared row before its own first harvest writes custom_icon. An empty
  # format suffix is correct here: application.scss styles
  # .twitter-profile-image round and only .icon-format-square overrides it.
  test "channel avatar renders round when the feed has no custom_icon yet" do
    with_env("R2_IMAGE_HOST" => "images.example.com") do
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCabc")
      assert_nil feed.custom_icon

      Image.create!(
        provider: :embed_icon, provider_id: "UCabc",
        url: "https://yt3.ggpht.com/large.jpg", variant: "200x200",
        image_fingerprint: SecureRandom.hex(16),
        original_fingerprint: SecureRandom.hex(16),
        storage_path: Image.content_storage_path_for(SecureRandom.hex(16), "200x200", "png"),
        width: 200, height: 200, bytesize: 4_000, placeholder_color: "aabbcc"
      )

      output = render FaviconComponent.new(feed: Feed.find(feed.id))

      assert_includes output.to_s, "twitter-profile-image"
      refute_includes output.to_s, "icon-format-square"
    end
  end
```

Append to `test/views/query_count_test.rb`, inside `class SidebarQueryCountTest`:

```ruby
  # The test above uses create_feeds, whose feeds all have a nil channel_id;
  # the lazy path queries anyway (provider_id IS NULL), so it catches a
  # dropped preload, but it never exercises the preloader's grouped lookup.
  # These feeds have a real channel_id, so the preload has to actually match
  # rows and its count has to stay flat.
  test "the sidebar does not query the channel avatar once per youtube feed" do
    login_as @user
    subscribe_to_channels(1)

    with_few = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }
    subscribe_to_channels(10)
    with_many = capture_sql { get :auto_update, params: {subscriptions_hash: "stale"}, xhr: true }

    assert_response :success
    pattern = /FROM "images"/i
    assert_equal matching(with_few, pattern).count, matching(with_many, pattern).count,
      "the sidebar's images lookup scales with the youtube feed count"
  end

  def subscribe_to_channels(count)
    count.times.map do
      id = "UC#{SecureRandom.hex(8)}"
      feed = Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}")
      @user.subscriptions.where(feed: feed).first_or_create
      feed
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/components/favicon_component_test.rb test/views/query_count_test.rb
```

Expected: FAIL — `Feed#channel_image_record` does not exist, so `icon_url` returns the signed proxy url and `FaviconComponent` renders it. The query-count test passes vacuously at this point (no association means no query); it is the guard for Step 4, not a currently-meaningful test.

- [ ] **Step 3: Read the channel row**

In `app/models/feed.rb`, add the association below the existing `has_one :icon_image_record` (line 16):

```ruby
  has_one :channel_image_record, -> { provider_embed_icon }, class_name: "Image", foreign_key: :provider_id, primary_key: :channel_id
```

and replace `icon_url` (line 106):

```ruby
  # The renderable URL for the feed's own icon. New artwork lives on an images
  # row and is served straight from our CDN; anything crawled before the R2
  # transition is a third-party url that still has to go through the signing
  # proxy. icon/icon_options/default_icon_format are untouched -- they still
  # answer "which source won and what shape is it", which is a different
  # question from "what do I put in the src attribute".
  #
  # The feed's own row outranks the channel's: icon_image_record is keyed on
  # this feed's id and belongs to it alone, while channel_image_record is one
  # row shared by every feed for the channel. In practice a feed is never both
  # a podcast and a YouTube channel, so the order is a tie-break that should
  # never be exercised.
  def icon_url
    Image.r2_url(icon_image_record&.storage_path) ||
      Image.r2_url(channel_image_record&.storage_path) ||
      (icon && RemoteFile.signed_url(icon))
  end
```

- [ ] **Step 4: Preload it everywhere `icon_image_record` is preloaded**

Every one of these renders `FaviconComponent` per row, and `icon_url` now reads a second association. Rails skips owners with a nil key when preloading, but it does **not** skip the per-row query for a persisted owner whose key is nil — so without this, a sidebar of ordinary feeds issues one `images` query per feed.

All 16 sites spell it identically, so one literal replacement covers them: `:favicon, :icon_image_record` → `:favicon, :icon_image_record, :channel_image_record`.

**Run this exactly once.** The replacement is not idempotent — its output still contains its own search pattern, so a second run produces `:channel_image_record, :channel_image_record`. If you are unsure whether it already ran, check with the doubled-form grep in the verification below before running it again.

```bash
source ~/.bash_profile && grep -rl ":favicon, :icon_image_record" app | xargs sed -i '' 's/:favicon, :icon_image_record/:favicon, :icon_image_record, :channel_image_record/g'
```

The files that must change, and no others:

- `app/models/entry.rb:57` (`entries_with_feed`)
- `app/models/action.rb:109`
- `app/models/user.rb:403` (`tag_group`)
- `app/jobs/cache_entry_views.rb:17`
- `app/controllers/application_controller.rb:227` (`get_feeds_list`)
- `app/controllers/entries_controller.rb:208, 255`
- `app/controllers/pages_entries_controller.rb:10, 20, 25`
- `app/controllers/queued_entries_controller.rb:6`
- `app/controllers/recently_played_entries_controller.rb:8`
- `app/controllers/recently_read_entries_controller.rb:6`
- `app/controllers/saved_searches_controller.rb:9`
- `app/controllers/settings/subscriptions_controller.rb:127`
- `app/controllers/updated_entries_controller.rb:6`

Verify the count, that the replacement did not double-apply, and that nothing else moved:

```bash
source ~/.bash_profile && grep -ro ":icon_image_record, :channel_image_record" app | wc -l; grep -rn ":channel_image_record, :channel_image_record" app; git diff --stat
```

Expected: `16`, no output at all from the doubled-form grep, and `git diff --stat` listing only the 13 files above plus `app/models/feed.rb`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
source ~/.bash_profile && bin/rails test test/models/feed_test.rb test/components test/views test/controllers
```

Expected: PASS. `test/components/favicon_component_test.rb`'s pre-existing `"feed icon"` test is the guard that the legacy fallback still renders the signed proxy markup byte for byte; if it fails, `icon_url`'s last branch is wrong — fix `icon_url`, not the test.

- [ ] **Step 6: Run the full suite**

```bash
source ~/.bash_profile && bundle exec rake
```

Expected: PASS. 1653 runs (30 added across all five tasks), 0 failures, 3 skips.

- [ ] **Step 7: Commit**

```bash
git add app/models/feed.rb app/models/entry.rb app/models/action.rb app/models/user.rb app/jobs/cache_entry_views.rb app/controllers test/models/feed_test.rb test/components/favicon_component_test.rb test/views/query_count_test.rb && git commit -m "Read YouTube channel avatars from the images row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

Adds 6 runs.

---

## Manual verification before merge

The suite covers the mechanics. These need eyes.

- [ ] **A real channel, end to end.** With a Sidekiq worker running and `R2_BUCKET_IMAGES` set, harvest a channel and confirm the row:

```ruby
feed = Feed.where.not(channel_id: nil).first
ImageCrawler::ChannelImage.schedule(Embed.youtube_channel.find_by_provider_id(feed.channel_id))
row = Image.find_by(provider: :embed_icon, provider_id: feed.channel_id)
[row&.storage_path, row&.width, row&.height, row&.original_fingerprint]
```

Confirm `storage_path` ends in `.png` and the dimensions are 200×200 or smaller. A source larger than 200 that came back at 200 means `limit` worked; a source of 88 that came back at 88 means it correctly refused to upscale.

- [ ] **The short circuit actually short-circuits.** Run the same schedule a second time and confirm no new `Process` job is enqueued and `row.reload.updated_at` is unchanged. That is the whole point of content-addressing, and it is the behavior that silently regresses if `unchanged?` ever stops matching.

- [ ] **A white avatar survives.** Find a channel whose avatar is a dark logo on a white background, schedule it, and confirm a row exists. Under `icon_crop` this would store nothing at all — that is the failure Task 1 exists to prevent, and it is invisible in production except as a missing icon.

- [ ] **Avatars render in the browser.** Sign in at `https://feedbin.resolv.app/auto_sign_in`, open a YouTube feed, and confirm the channel avatar appears in the sidebar and in the entry list, **round**, at the same size as before. Set `R2_IMAGE_HOST` and confirm it switches to the R2 host; unset it and confirm it falls back to the signed proxy without breaking.

- [ ] **The shared row is real.** For a channel with more than one feed row, confirm both resolve the same object:

```ruby
Feed.where(channel_id: "UC…").map(&:icon_url).uniq
```

Expect one element — that is "one row serves the channel's own feed and every playlist entry from it" made visible.

## Deployment notes

Run in this order:

1. Deploy (the migration adds `feeds.channel_id`, nullable, with a concurrent index — no lock, no backfill).
2. `BackfillFeedChannelIds.perform_async` from the console. Until it finishes, a YouTube feed whose `channel_id` is still nil renders its old proxied avatar and receives no `custom_icon` update from a harvest — a pause, not a break.
3. Harvests start storing avatars on their own from the next video in any subscribed channel. There is no sweep and no new scheduler, so coverage fills in over roughly a crawl cycle rather than all at once.

`R2_IMAGE_HOST` is the read cutover switch and is **shared with entry previews and podcast artwork** — if either has been cut over it is already set, so there is no accumulate-then-flip step for this tenant. Reads flip **per row, the instant that row is written**, and the fallback is per-feed rather than all-or-nothing.

There is no cache-key version bump, so no cold-cache wave. There is one bounded invalidation: `ChannelImage#perform` touches a channel's feeds the first time its avatar is stored, which re-renders the sidebar and entry lists for subscribers to that channel. Once, per channel, and never again unless the avatar actually changes.

Two new Librato series to watch, both pre-existing counters now reached by a third tenant: `image.icon_unchanged` should climb steadily (every re-harvest of an unchanged avatar) and `image.r2_resurrected` should stay at zero.

## What this plan deliberately leaves out

- **The WebSub half of `feeds.channel_id`.** `Feed#youtube_channel_id`, `#self_url`, `#known_hubs` and `#update_youtube_videos` are untouched. The design doc says the column replaces "the two current mechanisms"; this replaces the reverse lookup and leaves the guard. Pointing `self_url` and `known_hubs` at the wider column would change which feeds get a rewritten self_url and a PuSH subscription — plausibly more correct, entirely unrelated to icons, and capable of breaking feed updates if it is wrong. It also has to resolve the inconsistency the design flags, where `self_url` builds `/xml/feeds/videos.xml` and every other mechanism expects `/feeds/videos.xml`. Its own change.

- **Entry-level avatar rendering.** `provider_parent_id` is now set from the entry's own `<yt:channelId>` at creation, which is what makes a playlist entry resolvable to its real channel — but nothing renders a per-entry channel avatar today, so this phase adds no reader. `Entry` gets no `channel_image_record` association until something needs one; adding it now would be an unpreloaded `has_one` on the hottest collection render in the app.

- **`RemoteFilesController#icon` and the resize proxy.** They stay. The route (`icons/:signature/:url`) carries no size segment, so `params[:size]` is always nil and every request already collapses to the 400 branch — one stored variant replaces it exactly. But the same controller still serves Twitter avatars and adhoc images, which are `remote_file` and out of scope for the whole icon family. It retires with those.

- **Channel rows are never garbage collected, and that is a decision, not an oversight.** `ImageGarbageCollector` harvests from entry ids, and `Image.entry_owned` deliberately excludes `embed_icon`. A row keyed by a YouTube channel is owned by nothing that gets deleted — the same property the design doc records for host-scoped favicon rows in Phase E. `ImageReplacementCollector` still handles object churn as an avatar changes, which is the common case; what accumulates is one small row per channel ever harvested, and its 200×200 PNG. If that ever needs collecting, the harvest has to start from "channels no feed and no entry references any more", which is a different query from anything the collector does today.

- **`ImageReplacementCollector`'s legacy-S3 gap does not apply here.** It discards `sweep`'s return value and never enqueues `ImageDeleter`, which for podcast artwork can leave a legacy S3 object behind. `channel_avatar` is `legacy_store: false`, so there is no legacy object to leak.

- **The `channel_avatar` / `touch_icon` shared storage key.** Left shared on purpose, with a test pinning that the two recipes agree on single-layer sources. Phase E must not change `icon_crop`'s scaling without re-reading `test_icon_crop_and_limit_png_agree_on_a_single_layer_source` — and the design doc's "What Phases A and B learned" section is the right place to record that once this ships.
