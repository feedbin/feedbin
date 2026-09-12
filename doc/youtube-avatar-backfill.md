# YouTube avatar backfill

Deploy `BackfillChannelImages` before running these production Rails console
commands. The existing image pipeline and unified storage must be deployed and
configured. Feed channel IDs are already backfilled; FiveFilters wrapper
URLs without derivable IDs can be ignored.

The backfill uses cached `Embed.youtube_channel` metadata, including channels
without their own feed. It does not refresh metadata through the YouTube API or
change legacy `custom_icon` values. Existing `embed_icon` rows are skipped.

## What the run costs

Read this before the trial. The backfill is not free at the tail.

Each stored avatar fires the `ChannelImage` callback on the `default` queue.
That callback touches every feed for the channel. The sidebar and entry cache
keys include the feed, so the touch is required for the new avatar to appear.
At migration scale it invalidates the sidebar and entry caches of every
YouTube subscriber. Expect `default` queue depth to rise, and expect a period
of colder caches for YouTube feeds.

The schedule step pushes one `utility` job per 5,000 embed ids in one
call, the same fan-out `BackfillProviderIds` and `UpdateDefaultColumn` use,
with `at` timestamps spaced evenly over 12 hours. Each job scans its id
range for pending channels and pushes a `Find` job per channel onto the
shared `crawl_images` queue. Two things follow:

- The spread is the rate. At 1.9 million pending channels over 12 hours
  that is about 44 downloads per second, on top of live entry image
  crawling on the same queue. The image pipeline must sustain that, or
  `crawl_images` grows for the whole run and drains after the schedule
  ends.
- The rate toward `yt3.ggpht.com` is that same 44 per second, capped by
  the `crawl_images` concurrency. A refused download logs a `download
  exception` trace line and leaves the channel pending; nothing retries
  against Google. Grep the image worker logs for that line with `ggpht` in
  the URL during the first hour and compare it with `attempting image
  candidate` for the same period.

`Embed.youtube_channel` holds every channel ever harvested. This includes
channels nobody subscribes to and channels with no remaining entries. Those
cost a download for nothing. Compare `BackfillChannelImages.pending.count`
against the YouTube feed count before you commit to the full run.

## Outside camo fleet

YouTube rate-limits per address and Feedbin's addresses are static. The
download step can go through a fleet of `go-camo` hosts on other addresses.
Each host is stateless and reaches nothing of ours: Feedbin makes one
outbound HTTP request per fetch, signed with a key only the fleet shares,
and the host fetches the real URL from its own address. The row keeps the
YouTube URL, and the object is content-addressed on the original bytes, so
a channel fetched through the fleet and one fetched directly store the same
object.

Two environment variables on the image workers turn it on. Unset means
direct fetches.

```
CAMO_OUTSIDE_HOSTS=http://146.190.44.162,http://137.184.35.216,http://64.23.212.49
CAMO_OUTSIDE_KEY=<the key in /etc/go-camo/env on any fleet host>
```

`ChannelImage.schedule` picks one host per channel, so the run spreads over
every address. Only channel avatars use the fleet; live entry image crawls
fetch directly as before. When the run is over, unset both variables and
delete the hosts.

Each fleet host runs `go-camo` under systemd, listening on port 80, with
the key in `/etc/go-camo/env`. To check a host from the console:

```ruby
url = "https://yt3.ggpht.com/ytc/AIdro_kLLBqjbLLJfJf8qeqpcGxsPZC2eLa7RaHvbn6UUL5KRsw=s88-c-k-c0x00ffffff-no-rj"
puts ImageCrawler::OutsideCamo.hosts.map { |host| [host, Feedkit::Request.download(ImageCrawler::OutsideCamo.url(url, host)).status.code] }.inspect
```

Every host should answer 200.

## Trial

```ruby
# Channels without an avatar row, including missing thumbnails and failures.
puts BackfillChannelImages.pending.count

# Trial: the batch that holds the lowest pending id, run inline. Batches
# number embed ids in blocks of SidekiqHelper::BATCH_SIZE, starting at 1.
# Do not run the full migration concurrently with the trial.
batch = ((BackfillChannelImages.pending.minimum(:id) - 1) / SidekiqHelper::BATCH_SIZE) + 1
puts batch
trial_ids = BackfillChannelImages.batch_scope(batch).pluck(:id)
puts trial_ids.inspect
BackfillChannelImages.new.perform(batch)
```

Wait for the image Find, Process, Upload, and `default` (ChannelImage
callback) queues to drain. Then check the trial:

```ruby
trial_channels = Embed.youtube_channel.where(id: trial_ids)
puts Image.provider_embed_icon.where(provider_id: trial_channels.select(:provider_id)).count
puts BackfillChannelImages.pending.where(id: trial_ids).pluck(:id, :provider_id).inspect

# Inspect URLs and display a few migrated channels in the app.
puts Image.provider_embed_icon.where(provider_id: trial_channels.select(:provider_id))
  .limit(10).map { |image| [image.provider_id, Image.unified_url(image.storage_path)] }.inspect
```

Check a direct channel feed and a playlist entry with a different channel.
The channel row participates in entry cache keys; successful uploads touch
matching feeds for sidebar invalidation. Confirm round avatars and working CDN
URLs. A nil CDN URL means `UNIFIED_IMAGE_HOST` is missing.

## Full run and recovery

```ruby
BackfillChannelImages.perform_async(nil, true)
```

The schedule job pushes every batch up to the highest channel id at that
moment, so newly harvested channels do not extend the run. The batches sit
in Sidekiq's scheduled set and fire evenly over the next 12 hours. Each
batch logs `batch`, `scanned`, `scheduled`, and `no_thumbnail` counts. A
no-thumbnail line identifies the embed and channel. Scheduled counts are
not successful uploads.

### Rate knob

The third argument is the spread in seconds. It is read once, at schedule
time, so one call sets the pace for the run:

```ruby
# The same batches over 48 hours instead of 12: about 11 downloads per second.
BackfillChannelImages.perform_async(nil, true, 48.hours.to_i)
```

To slow a run that is already flooding the image queues: delete the
remaining `BackfillChannelImages` jobs from the Scheduled tab in the
Sidekiq web UI, wait for `crawl_images` to drain, then schedule again with
a longer spread. Batches whose channels are stored scan and push nothing,
so the rerun costs only the scans.

### Checking progress

After the image queues drain:

```ruby
puts BackfillChannelImages.pending.count
puts BackfillChannelImages.pending.order(:id).limit(20).map { |channel|
  [channel.id, channel.provider_id, channel.data.safe_dig("snippet", "thumbnails")]
}.inspect
```

Pipeline failures leave channels pending. Schedule again to retry them;
stored avatars are skipped. Do not overlap runs unnecessarily: channels still
in flight can be scheduled more than once, although row attachment upserts by
provider/channel. Utility jobs use normal Sidekiq retries; image pipeline jobs
do not, so an empty scheduled set is not proof of migration completion.

To retry one batch, take its number from the log line and call
`BackfillChannelImages.perform_async(batch)`.

Missing thumbnail metadata and permanently unavailable URLs remain pending for
manual review. Channels absent from `Embed.youtube_channel` are outside this
backfill. Keep legacy fallback reads and writes until coverage is accepted;
their retirement is a separate deployment after verification.
