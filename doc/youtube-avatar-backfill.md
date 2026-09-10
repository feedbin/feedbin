# YouTube avatar backfill

Deploy `BackfillChannelImages` before running these production Rails console
commands. The existing image pipeline and unified storage must be deployed and
configured. Feed channel IDs have already been backfilled; FiveFilters wrapper
URLs without derivable IDs can be ignored.

The backfill uses cached `Embed.youtube_channel` metadata, including channels
without their own feed. It does not refresh metadata through the YouTube API or
change legacy `custom_icon` values. Existing `embed_icon` rows are skipped.

## Trial

```ruby
# Channels without an avatar row, including missing thumbnails and failures.
BackfillChannelImages.pending.count

# Schedule at most 100 pending channels. Do not run the full migration
# concurrently with the trial.
trial_ids = BackfillChannelImages.pending.order(:id).limit(100).pluck(:id)
BackfillChannelImages.perform_async(0, trial_ids.last) if trial_ids.any?
```

Wait for the image Find, Process, Upload, and ChannelImage callback queues to
drain. Then check the trial:

```ruby
trial_channels = Embed.youtube_channel.where(id: trial_ids)
Image.provider_embed_icon.where(provider_id: trial_channels.select(:provider_id)).count
BackfillChannelImages.pending.where(id: trial_ids).pluck(:id, :provider_id)

# Inspect URLs and display a few migrated channels in the app.
Image.provider_embed_icon.where(provider_id: trial_channels.select(:provider_id))
  .limit(10).map { |image| [image.provider_id, Image.unified_url(image.storage_path)] }
```

Check a direct channel feed and a playlist entry with a different channel.
The channel row participates in entry cache keys; successful uploads touch
matching feeds for sidebar invalidation. Confirm round avatars and working CDN
URLs. A nil CDN URL means `UNIFIED_IMAGE_HOST` is missing.

## Full run and recovery

```ruby
BackfillChannelImages.perform_async
```

Each utility job scans at most 500 pending channels and schedules its successor
10 seconds later. This paces enqueueing; it does not cap image queue depth.
The run captures an inclusive maximum embed ID so newly harvested channels do
not extend it indefinitely. Each batch logs scanned/scheduled/no-thumbnail
counts, `last_id`, and `finish_id`. A no-thumbnail line identifies the embed and
channel. Scheduled counts are not successful uploads.

After the image queues drain:

```ruby
BackfillChannelImages.pending.count
BackfillChannelImages.pending.order(:id).limit(20).map do |channel|
  [channel.id, channel.provider_id, channel.data.safe_dig("snippet", "thumbnails")]
end
```

Pipeline failures leave channels pending. Rerun from the start to retry them;
stored avatars are skipped. Do not overlap runs unnecessarily: channels still
in flight can be scheduled more than once, although row attachment upserts by
provider/channel. Utility jobs use normal Sidekiq retries; image pipeline jobs
do not, so a finished utility chain is not proof of migration completion.

To resume only the unscanned portion of an interrupted run, pass the logged
`last_id` and `finish_id` as the two positional arguments to `perform_async`.
That does not retry failures before the cursor; rerun from the start afterward.

Missing thumbnail metadata and permanently unavailable URLs remain pending for
manual review. Channels absent from `Embed.youtube_channel` are outside this
backfill. Keep legacy fallback reads and writes until coverage is accepted;
their retirement is a separate deployment after verification.
