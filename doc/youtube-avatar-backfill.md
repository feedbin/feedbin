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

Image downloads land on the shared `crawl_images` queue. A large run competes
with live entry image crawling. Use the rate knobs below rather than a deploy
if the queue floods.

`Embed.youtube_channel` holds every channel ever harvested. This includes
channels nobody subscribes to and channels with no remaining entries. Those
cost a download for nothing. Compare `BackfillChannelImages.pending.count`
against the YouTube feed count before you commit to the full run.

## Trial

```ruby
# Channels without an avatar row, including missing thumbnails and failures.
puts BackfillChannelImages.pending.count

# Schedule at most 100 pending channels. Do not run the full migration
# concurrently with the trial.
trial_ids = BackfillChannelImages.pending.order(:id).limit(100).pluck(:id)
puts trial_ids.inspect
BackfillChannelImages.perform_async(0, trial_ids.last) if trial_ids.any?
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
BackfillChannelImages.perform_async
```

Each utility job scans at most `BATCH_SIZE` (500) pending channels and
schedules its successor `DELAY` (10) seconds later. This paces enqueueing; it
does not cap image queue depth. The run captures an inclusive maximum embed ID
so newly harvested channels do not extend it indefinitely. Each batch logs
scanned/scheduled/no-thumbnail counts, `last_id`, and `finish_id`. A
no-thumbnail line identifies the embed and channel. Scheduled counts are not
successful uploads.

### Rate knobs

The third and fourth arguments are the batch size and the delay in seconds.
They carry through the whole chain, so one call sets the rate for the run:

```ruby
# 100 channels every 60 seconds instead of 500 every 10.
BackfillChannelImages.perform_async(0, nil, 100, 60)
```

To slow a run that is already flooding the image queues: delete the scheduled
`BackfillChannelImages` job in the Sidekiq web UI, note the `last_id` and
`finish_id` from the last log line, then restart from that cursor with a
smaller batch size and a longer delay. A batch size below 1 is clamped to 1,
because `limit(0)` would end the chain and look like a finished run.

### Checking progress

After the image queues drain:

```ruby
puts BackfillChannelImages.pending.count
puts BackfillChannelImages.pending.order(:id).limit(20).map { |channel|
  [channel.id, channel.provider_id, channel.data.safe_dig("snippet", "thumbnails")]
}.inspect
```

Pipeline failures leave channels pending. Rerun from the start to retry them;
stored avatars are skipped. Do not overlap runs unnecessarily: channels still
in flight can be scheduled more than once, although row attachment upserts by
provider/channel. Utility jobs use normal Sidekiq retries; image pipeline jobs
do not, so a finished utility chain is not proof of migration completion.

To resume only the unscanned portion of an interrupted run, pass the logged
`last_id` and `finish_id` as the first two positional arguments to
`perform_async`. Repeat the batch size and the delay as well if the
interrupted run used non-default values; they do not survive the restart.
Resuming does not retry failures before the cursor; rerun from the start
afterward.

Missing thumbnail metadata and permanently unavailable URLs remain pending for
manual review. Channels absent from `Embed.youtube_channel` are outside this
backfill. Keep legacy fallback reads and writes until coverage is accepted;
their retirement is a separate deployment after verification.

## Known behavior: avatar flapping

`ChannelImage` offers every advertised thumbnail size as a candidate, largest
first. `Pipeline::Find` takes the first one that downloads. A transient
failure on the largest size therefore stores the smaller bytes, which changes
`original_fingerprint`, which flips `Image#url`, sweeps the old object, and
touches the channel's feeds. The next successful crawl of the largest size
flips it all back.

The cycle is bounded and it corrects toward the largest size. Each flip costs
one reprocess, one upload, one object sweep, and one cache invalidation. If
the flapping shows up in `image.icon_unchanged` or sweep volume, the fix is to
pin the ladder to the size the row already stored rather than to remove the
ladder.
