# The icon family: favicons, avatars, and artwork

**Status: draft, awaiting review**

Plan for moving every remaining image source into the `images` table: favicons, apple
touch icons, YouTube channel avatars, podcast show artwork, podcast episode artwork,
and adhoc remote files (Twitter avatars). Entry previews and link previews already
live there and are **not** changed by this plan.

The two mechanisms this family needs and previews do not:

1. **Storage keyed by the fingerprint of the original bytes**, not the URL. These
   sources mutate under a stable URL (`/favicon.ico` serves new bytes; a channel
   changes its avatar).
2. **Conditional HTTP on refresh**, so an unchanged source costs one 304 and no
   processing.

Plus one consequence that pays for itself: with the `Image` record in the view cache
digest, a shared icon changing invalidates every view referencing it **without
touching a single owner row** — deleting today's `TouchFeeds` fan-out.

## What is already right

The favicon crawler [already content-addresses by original bytes][processor]:

```ruby
def favicon_hash
  @favicon_hash ||= Digest::SHA1.hexdigest(File.read(@favicon[:original]))
end
# → File.join(favicon_hash[0..2], "#{favicon_hash}.png")
```

This plan generalizes that proven scheme rather than inventing one. `ConditionalHttp`
also already exists (`etag` + `last_modified` → request headers) and is reused as-is.

Two changes to that snippet when it moves, both matching what the pipeline already
does in [`Processed#fingerprint`][processed]:

- **MD5, not SHA1.** MD5 is 128 bits, so it stores in the `uuid` columns this table
  already uses for `url_fingerprint` / `image_fingerprint`; SHA1's 40 hex characters do
  not fit. Collision resistance is not a security boundary here — the same choice is
  already load-bearing for `image_fingerprint`.
- **`Digest::MD5.file(path).hexdigest`, not `Digest::MD5.hexdigest(File.read(path))`.**
  It streams the file through the digest in C instead of allocating the whole image as
  a Ruby string. Downloads already land on disk (`Download#persist!`), so a path is
  always what we have.

[processor]: ../../app/jobs/favicon_crawler/processor.rb
[processed]: ../../app/jobs/image_crawler/lib/processor/processed.rb

## Identity: two keys, deliberately separated

| key | question it answers | icon family | preview family |
|---|---|---|---|
| `url_fingerprint` | "have we seen this source URL?" | discovery/lookup only | dedup + reuse rules |
| `storage_path` | "which bytes is this?" | `MD5("<variant>|<original_fingerprint>").<ext>` | `MD5("<variant>|<url>").webp` |

**The icon family must not use `Dedupe`.** Skipping the download because a row already
exists for that URL is correct for previews — an og:image URL's content is fixed and
the entry never re-crawls — and exactly wrong for icons, whose whole problem is new
bytes at a stable URL. Icons always fetch, then short-circuit *after* the download on
an `original_fingerprint` match: no processing, no upload, no row write. That is the
same shape `Finder` already has, and it is why the fingerprint is of the original
bytes. `Pipeline::Find` therefore branches on the preset, not on `unified?` alone.

Two required changes fall out:

- **`storage_path_for` must take an extension.** It hardcodes `.webp` today; the icon
  family stays PNG (alpha, and the ICO best-layer logic depends on it).
- **Garbage collection must refcount by `storage_path`, not `url_fingerprint`.** Once
  storage identity is content-derived, the object is the shared resource and the URL is
  not a proxy for it. This is strictly more correct for previews too — two URLs serving
  identical bytes currently store two objects and refcount separately. The advisory
  locks move to the same key.

Why original bytes rather than processed bytes (which I proposed earlier and withdrew):
hashing the original lets the refresh path skip **processing**, not merely the upload.
For 32×32 favicon renders the vips work and the ICO layer selection are the expensive
part, and they are skipped entirely when the source has not changed.

## Refresh: keep the existing cadence, and the touch rule

**No new refresh scheduler.** Each tenant already has machinery that decides when to
look again, and it works: `FaviconCrawler::Finder` is triggered by subscription,
import, save-page, and feed-fixer events and gates itself with `updated_recently?`
(a one-hour window); feed and episode icons refresh as a side effect of the feed
crawl. Those keep driving. What changes is only where the result is written.

`FaviconCrawler::Finder` already implements most of this design:

```ruby
if @force || @favicon.data["favicon_hash"] != processor.favicon_hash
  # ...only then upload and update
end
@favicon.save
```

That is the original-bytes comparison, already skipping upload and DB churn when the
source has not changed. Three adjustments when it writes to `images` instead:

- `data["favicon_hash"]` (SHA1 of the original) becomes `original_fingerprint` (uuid
  column, `Digest::MD5.file(path).hexdigest`).
- `data["Etag"]` / `data["Last-Modified"]` move onto the row's `data` unchanged — the
  `images.data` jsonb is the right home for them: opaque HTTP metadata, read only when
  re-fetching that row's URL, never filtered on in bulk. Storing them *per row* rather
  than per host is what makes conditional requests safe again (below).
- The freshness gate reads the `Image` row's `updated_at` instead of the `Favicon`'s.

The only new column is `original_fingerprint`. **`checked_at` is not needed** — it
existed to drive a sweep that no longer exists.

**The touch rule still governs.** `updated_at` may change only when the bytes actually
change, because it is now the view cache key (next section). This falls out of the
existing structure for free: `@favicon.save` issues no UPDATE when no attribute
changed, so an unchanged icon does not bump its timestamp. Preserve that discipline
when porting — an unconditional `touch` or a "record that we checked" write would
invalidate every cached view referencing the icon on every crawl, which is the entire
cost this design exists to avoid. Worth an explicit test.

Replacement GC: when new bytes change `storage_path`, the previous object loses a
reference. This is the "orphaned by replacement" path — real for mutable tenants,
unreachable for previews (entries never re-crawl). It reuses `ImageGarbageCollector`'s
batched delete, keyed on the old `storage_path`, under the same lock.

### The conditional request is disabled today, and the new schema is what un-blocks it

`Finder#download_favicon` stores `Etag` / `Last-Modified` after every fetch but never
sends them — the headers are commented out, so `response.not_modified?` effectively
never fires and every crawl re-downloads the full icon. The "save processing time" half
of HTTP caching is present in skeleton and switched off.

Git says why. Commit `98c39d3e` ("Favicon finder fix", Nov 2025) commented them out and
added `break if response.not_modified?` to the candidate loop in the same change. Those
two facts together explain the bug: `all_favicon_urls` yields *several* candidates
(each `ICON_NAMES` link rel, plus `/favicon.ico`), but there is only one
`Etag`/`Last-Modified` pair on the host's `favicons` row — whichever URL won last time.
Sending those headers to a *different* candidate URL invites a 304 for content we have
never actually seen, and with the new `break`, one spurious 304 aborts the whole crawl
with `new_favicon = nil` — the favicon would simply stop updating. Disabling the
headers was the correct fix for a one-pair-per-host schema.

**Per-URL rows dissolve that constraint.** In the new model a row *is* a specific
source URL (`images.url`), so conditional headers can be sent only when re-fetching
that same URL, and other candidates get unconditional GETs. The header can never be
mismatched to a URL it did not come from, and a 304 then means exactly what the `break`
assumes it means: this icon is unchanged, stop. So re-enabling conditional requests is
in scope for the favicon migration — but as a deliberate step, keyed per URL, not as
an uncommented line.

## View cache invalidation replaces the fan-out

Today a favicon change fans out to every feed on the host:

```ruby
# Favicon#touch_owners → TouchFeeds
Feed.where(host: host).select(:id).find_in_batches do |feeds|
  Feed.where(id: feeds.map(&:id)).update_all(updated_at: Time.now)
end
```

That exists only because [`entries_cache_key`][helper] is `[entry, entry.feed, "v7"]` —
the favicon is not in the digest, so the feed's timestamp is used as a proxy for it.
For a host like medium.com that is 100,000 writes to invalidate views.

Put the record in the digest instead:

```ruby
def self.entries_cache_key(entry, icons = {})
  [entry, entry.feed, icons[entry.hostname], entry.preview_image_record, "v8"]
end
```

Cache keys are computed at render time from loaded records, so **one row update
invalidates every view that references it, at any scale**. `Favicon#touch_owners` and
`TouchFeeds` are then deleted outright.

The collection renders already support this: `_entries.js.erb` passes
`cached: ->(entry) { entries_cache_key(entry) }` and a `locals: {favicons:}` channel.
Two things must land together with it:

- **Preload host-scoped rows** the way `Favicon.for_entries` does — one query per
  render for the whole collection, passed through the existing locals channel. A cache
  key that triggers a query per row would trade 100k writes for an N+1 on every render.
- **`CacheEntryViews`** renders with `cached: true` (plain), which uses the bare entry
  key. It must move to the same lambda, or the warm cache and the live render will
  disagree about keys.

[helper]: ../../app/helpers/entries_helper.rb

## Per-tenant map

Scope is the source's natural owner — never the consumer. That is what keeps a
medium.com favicon change at one row regardless of feed count.

| tenant | provider | `provider_id` | variant | format | freshness | discovery |
|---|---|---|---|---|---|---|
| favicon | `website_favicon` | host (`"medium.com"`) | `32x32` limit | png | ~1 week | `FaviconCrawler` (link rels, `/favicon.ico`) |
| apple touch icon | `website_touch_icon` | host | `200x200` limit | png | ~1 week | same crawl, same page fetch |
| YouTube channel avatar | `embed_icon` | channel id (`"UC…"`) | `200x200` limit | png | every harvest | `HarvestEmbeds` |
| podcast show art | `feed_icon` | feed id | `200x200` limit | png | feed crawl | feed options (`itunes_image`, `json_feed.icon`) |
| podcast episode art | `entry_icon` | entry id | `200x200` limit | png | never | `ItunesImage` |

**`variant` names the rendering recipe, not the result.** This has not mattered until
now — every preset was a fill crop, so the spec and the output agreed. Touch icons use
`limit_crop` ("up to 200×200", preserving aspect ratio and never upscaling), so a
180×180 source stays 180×180 while its variant is still `200x200`. Keying on the recipe
is what makes two renditions of the same recipe interchangeable; keying on the actual
output would fragment the namespace and break dedup. `ImageCrawler::Image#variant`
already derives from the preset, so it is correct as written — but it needs a test that
pins the limit case, since a fill-only world never exercised the distinction.

Notes on the shape of this table:

- **Favicons keyed by host** is the whole answer to the medium.com question: feeds and
  entries resolve by hostname at render time and hold no copy.
- **Favicon and touch icon are separate rows for one host**, distinguished by provider,
  which `(provider, provider_id)` already supports. `FaviconCrawler::Finder` already
  discovers both — `ICON_NAMES` includes `apple-touch-icon` and
  `apple-touch-icon-precomposed` — but today they are pooled as interchangeable favicon
  candidates and the best single layer wins. The change is to route them to their own
  provider and render at their own variant, from the same page fetch.
- **Every surface keeps rendering the favicon variant for now.** Touch icons are
  collected but not consumed: no component chooses between the two, and no fallback
  order has to be designed yet. That keeps the migration's blast radius at "the favicon
  looks the same as before" while the ≤200×200 rows accumulate for whatever wants them
  later. Two things follow: store whatever a host advertises even when it is small (a
  60×60 `apple-touch-icon` gives a 60×60 row at variant `200x200`, since `limit` never
  upscales) and record real `width`/`height`, so a future consumer can filter by size
  without re-fetching; and expect no visual signal if touch-icon rendering is wrong
  until something displays them — worth a spot-check by hand rather than trusting the
  absence of complaints.
- **Episode art never refreshes**: entry-scoped, effectively immutable, and the entry
  is deleted before staleness matters. It still uses original-bytes keying — uniform
  across the family, and it costs nothing.
- **`remote_file` is deferred** — Twitter avatars and adhoc images stay on the existing
  `RemoteFile` model for now. YouTube channel avatars are the one thing pulled *out* of
  that path early (next section), because they have a real owner to key on.

## YouTube channel avatars

Today these are not really stored at all — they are hotlinked, then cached lazily by a
proxy on first render:

1. `HarvestEmbeds::Download#update_related_records` copies
   `channel.data["snippet"]["thumbnails"]["default"]["url"]` (a **88×88** ggpht URL)
   into `feed.custom_icon`.
2. `FaviconComponent#icon_feed` renders `RemoteFile.signed_url(@feed.icon)` — a signed
   Feedbin proxy URL.
3. `RemoteFilesController#icon` looks the URL up in `remote_files` and, **on a miss**,
   fires `CacheRemoteFile.schedule(url)` and proxies the origin in the meantime.

Three problems fall out: the first viewer of any channel gets a cold miss served
straight from Google; the stored source is 88×88, which is soft in every slot bigger
than a favicon; and the avatar is keyed by URL, so nothing connects it to the channel it
belongs to.

Proposed instead — download at harvest time, keyed by the channel:

- **Hook:** `HarvestEmbeds::Download`, where `youtube_channel` embeds are imported.
  Schedule the avatar through the shared pipeline there, so it is stored before anything
  renders it.
- **Scope: the channel, not the feed and not the entry.** `provider_id` is the YouTube
  channel id, so **one row serves both** the channel's own feed *and* every playlist
  entry from that channel — the case that motivated splitting feed-level from
  entry-level in the first place. Entries already carry `provider_parent_id` (the
  channel id), so they resolve directly with no new column.
- **Take the largest thumbnail, not `default`.** The channels API returns
  `default` (88×88), `medium` (240×240) and `high` (800×800); picking `high` and
  limiting to 200×200 is a straight quality win over today's 88×88.
- **Refresh is already handled**: `Embed.import(on_duplicate_key_update: {columns:
  [:data]})` refreshes channel data every time any video from that channel is
  harvested, so the avatar is re-checked on the existing cadence. No new scheduler,
  consistent with the rest of this plan. The `original_fingerprint` comparison keeps an
  unchanged avatar from costing an upload, a row write, or a view invalidation.
- **Losing the resize proxy costs nothing in practice.** `RemoteFilesController` can
  serve 32/64/128/200/400, but the route (`icons/:signature/:url`) carries no size
  segment, so `params[:size]` is always nil and every request is 400. One stored variant
  replaces it exactly.

### Resolving the channel: both sides already have the data

**Feedkit needs no changes.** It already extracts `<yt:channelId>` at both levels —
`xml_feed.rb` puts it in the feed's options, `xml_entry.rb` lists `youtube_channel_id`
among the entry attributes — and Feedbin already persists both. Verified against a live
row: `entries.data["youtube_channel_id"] == "UC6t1O76G0jYXOAoYCm153dA"` and
`feeds.options["youtube_channel_id"]` present.

**Feeds: promote it to a column.** `feeds.channel_id`, populated from the parsed feed,
replacing the two current mechanisms:

- `Feed#youtube_channel_id` derives the id by regex from `feed_url` *and* `self_url`,
  requiring both to match. That is a guard, not a parse, and it returns nil for
  playlist feeds — correct, since a playlist is not a channel.
- `HarvestEmbeds` does the reverse lookup by reconstructing a URL string:
  `Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=…")`.
  An indexed `channel_id` column makes that a real query and stops it depending on one
  exact URL spelling — note `Feed#self_url` builds `/xml/feeds/videos.xml` while the
  lookup and the regex expect `/feeds/videos.xml`, so the string form is already
  inconsistent within the model.

Decide the precedence when both exist (parsed XML vs URL-derived); they should agree,
and where they do not, the parsed value is the source of truth.

**Playlist entries resolve at parse time, no API needed.** Each `<entry>` in a YouTube
feed carries its own `<yt:channelId>`, so a playlist whose videos come from many
channels gives every entry the right channel from the XML alone — already landing in
`entries.data["youtube_channel_id"]`.

Today `provider_metadata` only sets `provider_parent_id` when an `Embed` row *already*
exists, otherwise leaving it for `HarvestEmbeds#update_related_records` to backfill
after the API round trip:

```ruby
self.provider_id = data["youtube_video_id"]
if embed = Embed.youtube_video.find_by_provider_id(self.provider_id)
  self.provider_parent_id = embed.parent_id
end
```

Set it from `data["youtube_channel_id"]` instead, falling back to the embed lookup.
The channel is then known the moment the entry is created — so the avatar resolves on
first render rather than after a harvest, and it keeps working when the YouTube API is
rate-limited, erroring, or the video has been made private (all cases where
`video_items` comes back empty today).

## Icon presets and processing

The icon family gets its own presets in `ImageCrawler::Image::PRESETS`, built on the
favicon crawler's processing rather than the entry-preview cropper's. Those are
genuinely different jobs: entry previews smart-crop a photograph to a fixed 16:9 frame;
icons pick the best layer out of a multi-layer source and scale it whole.

Two presets, sharing everything but their sizing rule:

| preset | sizing | why |
|---|---|---|
| `favicon` | `resize_to_limit(32, 32)` | up to 32×32 — 2× the 16 CSS px box it renders into |
| `touch_icon` | `resize_to_limit(200, 200)` | up to 200×200 — a 180×180 source stays 180×180 |

Both keep the rest of `FaviconCrawler::Image`'s behaviour: `ImageFormat.allowed?`
gating, the ICO **best-layer selection** (largest layer whose average colour is not
nil / transparent-black / white), `strip: true`, and PNG output.

**SVG sources rasterize** at the preset's size, like any other input — vips handles
this through librsvg, and `ImageFormat` already accepts SVG. One rendition per variant,
no format branch, and the stored object stays a PNG whose bytes are content-addressed
like everything else. The tradeoff is accepted knowingly: an SVG favicon could scale to
any size, and we are freezing it at 32×32 (and ≤200×200 for the touch icon). Rasterize
from the SVG at the target size rather than from a smaller raster candidate when both
are advertised, so the result is sharp.

`limit`, not `fit`, for both — upscaling fabricates no detail, it only makes a larger
file that is equally soft. This is a deliberate change from today's favicon output,
which uses `resize_to_fit(32, 32)` and therefore upscales a 16×16 source to 32×32.
Verified safe: `.favicon-wrap .favicon` is pinned to `background-size: 16px 16px` with
a 16×16 box, so the intrinsic size never affects layout. Sources already ≥32×32 (most
sites now ship 32, 48, or 180 px icons) are unaffected — they downsize to 32×32 and
stay 2× sharp. The only sites that change are ones shipping nothing larger than a
16×16 `favicon.ico`: their icon stays 16×16 and is soft on retina, which it already
effectively was, since the upscale carried no additional information.

Mechanics this requires:

- **The layer selection must be shared, not copied.** `FaviconCrawler::Image#best_layer`
  and its `INVALID_COLORS` heuristics keep running in the legacy crawler throughout the
  migration; forking them into the new preset guarantees the two drift. Extract into
  `Processor::IconLayer` (or equivalent) and have both call it.
- **`Cropper#crop!` hardcodes `"jpg"`** for non-`limit_crop` strategies today. Icon
  presets need PNG, so the output format becomes a property of the preset rather than
  of the method.
- **Favicons dual-write, the same as entry previews did.** `FaviconCrawler::Finder`
  keeps writing the `favicons` row and its S3 object exactly as today, *and* feeds the
  shared pipeline so an `images` row and its R2 object are produced alongside. Rows
  accumulate while nothing reads them; cutover is switching the read; the legacy
  crawler is retired only after that has baked. The one difference from previews is
  that this is dual-*store*, not dual-*format*: `crop_pair!` (jpg + webp) is not used,
  because the legacy favicon object already exists in its own bucket and the new path
  writes a single PNG.
- **The transition costs a second fetch per crawl** — the legacy crawler downloads, and
  the pipeline downloads again. Acceptable and temporary: favicon crawls are
  event-triggered (subscribe, import, save-page, feed-fixer), not a sweep, and it ends
  when the legacy crawler is retired. Handing the already-downloaded file to the
  pipeline instead would save the fetch at the cost of bypassing
  `Pipeline::Find`/`Download`, which is the structure worth keeping during a migration.
- **PNG means `storage_path` must carry the extension** (Phase A), and the immutable
  cache headers stay correct because the key is content-derived.

## Phases

Each phase is independently shippable; tenants migrate one at a time behind the
existing pattern (flag the preset in, add the association and row-first reads,
touch-only callback, retire the legacy store).

**Phase A — foundation** (no tenant moves)
- `storage_path_for` takes an extension; output format becomes a preset property.
- GC + advisory locks refcount by `storage_path`; replacement-GC path.
- Add `original_fingerprint`; icon presets and the extracted `Processor::IconLayer`.

**Phase B — cache digest**
- `entries_cache_key` gains image records; host-scoped preload; `CacheEntryViews`
  moves to the lambda; sidebar `_feeds.html.erb` key gains feed icons.
- Delete `Favicon#touch_owners` and `TouchFeeds`.

**Phase C..E — tenants, easiest first**
1. Podcast/iTunes (`entry_icon`, `feed_icon`) — biggest dedup win (one object per show
   instead of one per episode) and fixes the episode-art deletion leak. Episode art
   never refreshes, so it exercises the new storage keying in isolation.
2. YouTube channel avatars (`embed_icon`) — hooks `HarvestEmbeds`, keyed by channel;
   first tenant whose icons genuinely change over time, and the first to retire a
   hotlink. Ships with two small prerequisites: the `feeds.channel_id` column, and
   `provider_metadata` setting `provider_parent_id` from `data["youtube_channel_id"]`.
   `Feed#icon_options` precedence must be preserved.
3. Favicons **and touch icons together**, last — one crawler, one page fetch, two
   providers; largest blast radius, and it depends on Phase B being proven. Sequenced
   internally like the entry-preview migration: dual-write until rows have accumulated
   → flip the read → bake → retire the legacy crawler, its bucket, and the `favicons`
   table. Per-URL conditional requests get re-enabled in the same phase, once rows own
   their own `Etag`/`Last-Modified`.

`remote_file` is out of scope for now and keeps its existing model and bucket.

## Open questions

None outstanding. Decisions settled during design, recorded here so they are not
relitigated: `remote_file` deferred; `favicons.favicon` (base64) is dead and ignored;
every surface keeps rendering the favicon variant, with touch icons collected but not
yet consumed; both icon presets use `resize_to_limit`; SVG sources rasterize; the
existing per-tenant refresh cadence stays and no new scheduler is built; favicons
dual-write through the shared pipeline during the transition; `Etag`/`Last-Modified`
live in `images.data`, per row; YouTube channel avatars are keyed by channel and
resolved through a denormalized `feeds.channel_id` plus the existing
`entries.provider_parent_id`.

## Out of scope

`ImageSaver` (the archive bucket) stays separate: it preserves exact original bytes of
content images, with no derivation and a lifecycle tied to the user's save. Camo stays
separate: it is a live proxy, not storage.
