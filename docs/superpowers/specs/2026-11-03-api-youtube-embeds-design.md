# YouTube embeds in API v3

## Intent

The website turns every YouTube iframe in an entry into a card: the video's
poster with its duration and a play button, the channel avatar, title and
channel name, and a chapter list that jumps the video to each chapter. API
clients (Feedbin's own apps first) get none of that: they show YouTube's bare
iframe, so there are no chapters, no duration, and nothing until YouTube's
player loads.

The goal is the same experience in the apps as on the website. The API
provides the data; each client draws the card natively and loads the YouTube
iframe only when the reader taps play.

## What exists today

- `Entry#harvest_embeds` (app/models/entry.rb:606) queues `HarvestEmbeds` when
  an entry with an iframe, a micropost or a YouTube video is created.
  `HarvestEmbeds#find_embeds` collects YouTube ids from the content's iframes
  and links plus `data["youtube_video_id"]`, and queues the ones without an
  `Embed` row. The clock drains the queue every minute, 50 ids per YouTube
  Data API call (`HarvestEmbeds::Download`).
- `Embed` rows: a `youtube_video` row per video (YouTube's `videos` resource:
  snippet, contentDetails, liveStreamingDetails) and a `youtube_channel` row
  per channel. `Embed#duration_in_seconds` and `Embed#chapters`
  (`TextToChapters` over the description) derive the card's data. The
  channel's avatar is an `Image` row (`Embed#channel_image`, crawled by
  `ImageCrawler::ChannelImage`).
- Scheduled live streams are re-harvested an hour after they start
  (`requeue_live_videos`).
- A YouTube channel entry (`data["youtube_video_id"]`) gets its player iframe
  prepended by `ContentFormatter.source_html`, so its video is an iframe in
  `content.html` like any other.
- The website asks `/embeds/iframe` per iframe on load; that endpoint builds
  the card from `IframeEmbed::Youtube`, which uses YouTube's oEmbed for the
  title and poster and the `Embed` rows for the rest
  (app/views/embeds/iframe_view.rb).
- The API's `content.html` (`ContentFormatter::Api`) passes the iframe
  through untouched.

## Decisions

These were decided with Ben:

1. **Data comes with the entry, not on demand.** Every v3 entry object
   carries a `videos` list. There is no per-embed request for clients to
   make.
2. **Always included, not behind `expand=`.** An entry with no YouTube
   videos has `videos: []`.
3. **YouTube only.** Vimeo stays a bare iframe in the API. The website's
   Vimeo cards come from on-demand oEmbed and there is no stored Vimeo data.
4. **Late data reaches clients as an edit.** When a harvest stores data for
   videos, every entry that embeds those videos is marked edited (its
   `revision` incremented and `edited_at` set), so a client following
   `sort=edited_asc` refetches it with the data.
5. **The API sends data, not card HTML.** The client builds the card and
   swaps in the iframe on play.

## The `videos` list

One item per distinct YouTube video whose iframe appears in the entry's
`content.html`, in order of first appearance. A video whose `Embed` row is
missing (harvest pending, deleted, private, region-blocked) is left out; the
client shows the plain iframe for any iframe with no matching item.

Proposed shape (field names are the builder's to refine against the v3
conventions):

```json
{
  "object": "video",
  "provider": "youtube",
  "id": "dQw4w9WgXcQ",
  "url": "https://youtu.be/dQw4w9WgXcQ",
  "title": "…",
  "duration_in_seconds": 213,
  "live": "none",
  "scheduled_start_at": null,
  "poster": {"url": "https://i.ytimg.com/vi/…/maxresdefault.jpg", "width": 1280, "height": 720},
  "channel": {
    "id": "UC…",
    "title": "…",
    "icon": { …image object, as ImageSerializer, or null… }
  },
  "chapters": [
    {"start_in_seconds": 0, "title": "Intro", "duration_in_seconds": 42}
  ]
}
```

- `id` is the YouTube video id. A client matches an iframe to an item by the
  id in its `src`, using the patterns in config/initializers/youtube.rb
  (`/embed/{id}`, youtube-nocookie, shorts and so on).
- `title`, `poster` come from the `Embed` row's snippet, not oEmbed. `poster`
  is the largest thumbnail the snippet lists (maxres, then standard, high,
  medium, default).
- `live` is YouTube's `liveBroadcastContent` (`none`, `upcoming`, `live`), so
  a client can label an upcoming or live stream and not show a duration that
  means nothing yet.
- `channel.icon` is the channel's avatar `Image` row through the existing
  `ImageSerializer`, or null when it hasn't been crawled. `channel` is null
  when the channel row is missing.
- `chapters` is `Embed#chapters`, empty when the description has none. The
  last chapter's duration is null when the video's duration is unknown.

## Serving it

- Entry pages are served in batches (`Entry.for_api_v3`). The `videos` lists
  for a page must be loaded together: the video ids of every entry on the
  page, then one query for their `Embed` video rows, one for the channel
  rows, one for the channel avatar images. No per-entry queries.
- The video ids of an entry are those of the YouTube iframes in its API
  rendering. Reading them must not cost a full HTML parse of every entry on
  every response; the builder chooses how (a scan of the stored rendering
  for iframe srcs, or ids recorded when the entry is rendered).
- The data is read at response time, not stored in the rendering, so a later
  re-harvest (a live stream that ended, a description that gained chapters)
  shows up without re-rendering entries.

## Marking entries edited

- When `HarvestEmbeds::Download` stores rows, it finds the entries that embed
  any of those videos and bumps their `revision` and `edited_at`, as
  `FeedCrawler::EntryUpdate` does for content edits.
- Only entries created before the harvest need this; an entry served after
  its data exists already carries it. A bump per entry per harvest, not per
  video, when an entry embeds several videos harvested in one batch.
- Finding the entries: YouTube channel entries by `provider_id`
  (already done for `embed_duration`); entries that embed a video in their
  content need a way to be found by video id. The builder chooses it (a
  recorded entry-to-video mapping when entries are harvested, or the ids
  `find_embeds` already computed, held until the download).
- Re-harvests of live streams bump the entries again, so a stream that has
  started or ended reaches clients.
- **A channel avatar that lands later bumps again** (decided with Ben). The
  first time a channel is seen, `ImageCrawler::ChannelImage` crawls its
  avatar after the harvest has stored the rows and bumped the entries, so
  those entries go out with `channel.icon: null`. When that crawl stores the
  avatar, the entries that embed that channel's videos are bumped once more.
  The entry lookup therefore has to work by channel id as well as by video
  id. A crawl that fails or finds no avatar bumps nothing.
- No backfill. v3 is not on `main` and no client has synced with it, so
  entries carry `videos` from the first response any client sees; entries
  harvested before this ships need no bump, only the lookup mapping if the
  builder's chosen mapping is recorded at harvest time (then existing
  entries need it backfilled so later avatar and live-stream bumps find
  them).

## Non-goals

- Vimeo, Instagram or any other iframe provider.
- YouTube links (`<a href>`) as opposed to iframes. `HarvestEmbeds` collects
  linked videos too, but the website only makes cards from iframes, and so
  does this.
- Videos inside a micropost's `extracted.content.html` (the linked
  article). The website cards those, but `HarvestEmbeds` never harvests
  them; they stay bare iframes for now. (Claude's call.)
- Changing `content.html`. The iframe stays as it is, so clients that don't
  know about `videos` keep working.
- The website's card. It keeps working as it does.

## Anti-goals

- Clients making a request per video.
- A shape that only Feedbin's apps can use: third-party clients read the
  same entry objects.
- Breaking the v3 ETags or cursors: the edit bump must flow through the
  mechanisms that already exist.

## Left to the builder

- Exact field names and nesting, within the v3 conventions.
- How video ids are read from a rendering, and how entries are found by
  video id for the edit bump.
- Whether the poster should be proxied (Camo) for clients that honor the
  `proxy_images` preference, as the website proxies it.
- Tests and the v3 API documentation.
