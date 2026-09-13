# Feed icon backfill

Deploy the `feed_icon` image preset, `ImageCrawler::FeedIcon`, and
`BackfillFeedIcons` together, then run these production Rails console
commands.

`BackfillFeedIcons` schedules `ImageCrawler::FeedIcon` for feeds with a
legacy icon source in `options` (the RSS `<image>`, the JSON Feed `icon`,
or the JSON Feed author avatar) and no `feed_icon` row yet. It does not
touch podcasts: `ItunesFeedImage` owns their `feed_icon` row, and a feed
with `itunes_image` set is declined. The RSS `<image>` counts only for a
micropost feed, since for an article feed it is as often a banner as a
logo; `BackfillFeedIcons.pending` overestimates on purpose because that
check reads the feed's entries, which is not cheap in SQL, so the job
declines those feeds one by one at no download cost instead of filtering
them out up front. Declines are expected and are not a failure.

## Pre-deploy checks

The channel branch now reads the row's `kind` to choose round or square,
instead of assuming every `embed_icon` row is a channel avatar, so an
unlabeled channel row would render square. Likewise a `feed_icon` row
mislabeled `poster` would render square where it should be a favicon-style
icon.

```ruby
puts "embed_icon rows not labeled avatar (must be 0): #{Image.provider_embed_icon.where.not(kind: :avatar).count}"
puts "feed_icon rows still labeled poster (should be 0): #{Image.provider_feed_icon.where(kind: :poster).count}"
```

Both should read 0. If either does not, the kind backfill (`doc/image-kind-backfill.md`)
has not finished or missed rows; do not start this backfill until they are
clean.

## Rollout note

`ImageCrawler::FeedIcon.schedule` writes a `Pipeline::Find` job carrying
`preset_name: "feed_icon"`. During the deploy window, if an old-code image
worker picks up that job before the new code is live everywhere, it does
not recognize the `feed_icon` preset and the job dies without writing a
row (`sidekiq_options retry: false`, so it does not retry). Nothing is
corrupted: the feed simply stays pending, and the next subscribe or feed
create re-enqueues `ImageCrawler::FeedIcon` and self-heals it.

## Trial

```ruby
# Trial: the batch that holds the lowest pending feed id, run inline.
# Batches number feed ids in blocks of SidekiqHelper::BATCH_SIZE, starting
# at 1.
puts BackfillFeedIcons.pending.order(:id).limit(1).pluck(:id).first
```

Take the id the last line printed as `feed_id`, then:

```ruby
batch = ((feed_id - 1) / SidekiqHelper::BATCH_SIZE) + 1
BackfillFeedIcons.new.perform(batch)
```

## Full run

```ruby
BackfillFeedIcons.perform_async(nil, true)
```

The schedule job pushes every batch, spread evenly over `BackfillFeedIcons::SPREAD`
(1 hour by default) so the shared image queues are not hit all at once.
The set is small (a few thousand JSON Feed icons plus the micropost feeds
with an RSS image; article feeds with an RSS banner are filtered out in
SQL), so an hour spreads a few thousand downloads over about 670 batches.
To run over a different window, pass the spread in seconds as the third
argument, read once at schedule time:

```ruby
# The same batches over 6 hours instead of 1.
BackfillFeedIcons.perform_async(nil, true, 6.hours.to_i)
```

## Watching it

Each batch logs a line:

```
BackfillFeedIcons: batch=... scanned=... scheduled=... declined=...
```

Scheduled counts are not successful downloads; `scheduled` only means a
`Pipeline::Find` job was pushed. Check row counts and the retry queue,
ideally twice a day apart so the trend is visible:

```ruby
puts "pending: #{BackfillFeedIcons.pending.count}"
puts "feed_icon rows: #{Image.provider_feed_icon.count}"
puts "FeedIcon retries (must be 0): #{Sidekiq::RetrySet.new.count { it.klass == "ImageCrawler::FeedIcon" }}"
```

`FeedIcon` sets `retry: false`, so that count should always read 0; a
nonzero count means something upstream re-enqueued through a retrying
path and is worth investigating on its own.

When the run has mostly drained, list what is left:

```ruby
residual = BackfillFeedIcons.pending.order(:id).limit(50).pluck(:id, :feed_url)
puts "residual total: #{BackfillFeedIcons.pending.count}"
residual.each { |id, url| puts "  #{id} #{url}" }
```

## Residual feeds

A feed left in `BackfillFeedIcons.pending` after Deploy 2 is not broken:
it renders its host's favicon (`Feed#site_favicon`) until something
crawls a `feed_icon` row for it, and falls back further to the generated
placeholder if even the favicon is missing. Reruns are safe: a feed with a
stored `feed_icon` row leaves `pending`, and image attachment upserts by
provider and feed, so scheduling a feed twice while it is in flight does
not create duplicate rows.
