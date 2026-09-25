# Avatar backfill

Deploy the `micropost_avatar` image preset, `ImageCrawler::MicropostAvatar`
and `BackfillMicropostAvatars` together (Deploy A of the avatar images
cutover), then run the production Rails console commands below. From the
deploy on, each crawl's new micropost entries get their avatar rows from
the live pass; the backfill covers what was stored before.

This migration is about microposts only. Tweet avatars stay on the icon
proxy and `remote_files`, which is frozen from the deploy on: a miss is
served through camo and cached nowhere.

`BackfillMicropostAvatars` walks every micropost feed with an untitled
entry lacking an `entry_icon` row and runs
`ImageCrawler::MicropostAvatar.schedule` for it off the critical queues.
Entries that share an avatar url share one download, and a url another post
already stored is attached with no request. A download tries the source
first, then the object the proxy cached in the legacy icons bucket, so a
dead source still lands. It fans out in the `SidekiqHelper` style, one job
per `SidekiqHelper::BATCH_SIZE` feed ids on the `utility` queue, with `at`
timestamps spread over `BackfillMicropostAvatars::SPREAD` (one hour by
default) so the downloads share the crawl queues' rate limits with live
crawling, not all at once.

## Before deploying

These run on the code that is live now:

```ruby
puts "unlabeled podcast art rows (must be 0): #{Image.provider_entry_icon.where(Image.data_projection("preset").eq("podcast")).where.not(kind: :cover_art).count}"
puts "YouTube channels with no avatar row: #{Embed.youtube_channel.where.missing(:channel_image).count}"
```

`Entry#itunes_image` reads the row's kind from the moment of the deploy,
so an unlabeled podcast art row would drop an episode's own art: do not
deploy until the first count reads 0. The YouTube channels with no row show
the channel's thumbnail url on their card until `BackfillChannelImages`
covers them.

## Trial

The batch that holds the lowest pending feed id, run inline:

```ruby
feed_id = BackfillMicropostAvatars.pending.order(:id).limit(1).pluck(:id).first
if feed_id.nil?
  puts "nothing pending"
else
  batch = ((feed_id - 1) / SidekiqHelper::BATCH_SIZE) + 1
  puts "first pending feed: #{feed_id}, batch: #{batch}"
  puts "pending feeds in that batch: #{BackfillMicropostAvatars.batch_scope(batch).count}"
  BackfillMicropostAvatars.new.perform(batch)
  puts "attached and scheduled: see the BackfillMicropostAvatars log line above"
end
```

## Full run

```ruby
BackfillMicropostAvatars.perform_async(nil, true)
```

## Watching it

```ruby
puts "pass pending: #{BackfillMicropostAvatars.pending.count}"
puts "entry_icon avatar rows: #{Image.provider_entry_icon.where(kind: :avatar).count}"
puts "pass batches waiting to retry: #{Sidekiq::RetrySet.new.count { it.klass == "BackfillMicropostAvatars" }}"
```

A feed that raises is logged (`BackfillMicropostAvatars: feed failed
feed_id=...`), stays pending, and the rest of its batch goes on, so a batch
in the retry set failed as a whole and is worth a look.

The pass's pending count does not reach 0: an untitled entry that is not a
micropost, has no avatar, belongs to a podcast episode, or whose avatar
never lands keeps its feed pending. It is also prefiltered by the parser's
marker for a micropost feed, so a micropost feed without the marker is not
covered here; its new posts are, from its next crawl, but its older
entries are not.

## The gate before Deploy B

`BackfillMicropostAvatars.pending.count` must hold steady across two checks
a day apart. Then confirm in the browser: an entry list with microposts and
a micropost entry view show no `/files/icons/` url except for feeds still
pending, and `image.unified_error` is flat. Stored tweets keep their
`/files/icons/` urls; that is expected.

**Deploy B changes:**

- `Image.avatar_url` serves a miss through camo instead of
  `RemoteFile.signed_url`, so an avatar no row holds still renders while its
  source lives: a new replier in the micro.blog replies dialog, or a post
  whose row has not landed.
- `Feed#icon_url`'s `RemoteFile.signed_url(icon)` fallback and
  `FaviconComponent#legacy_icon_format` go with the feed icon cutover's
  Deploy 2.
- The legacy object candidates in `ImageCrawler::FeedIcon.schedule` and
  `ImageCrawler::MicropostAvatar.enqueue`, and `RemoteFile.legacy_object_url`.
- Every other line marked `# Deploy A only`.
- Bump `entries_helper`'s cache key from `"v15"` to `"v16"` and both of
  `feeds_helper`'s version strings, so fragments cached during Deploy A
  re-render against the rows.

The proxy route, `RemoteFile.signed_url`, the `remote_files` table and the
legacy icons bucket stay: tweet avatars read them.

## Residual avatars

A residual left after Deploy B is not broken, it degrades: an avatar that
no row holds renders through camo while its source lives, and the default
avatar once it is gone. Reruns are safe: an attached row leaves `pending`,
and `Image.attach!` upserts, so scheduling the backfill twice while it is in
flight does not create duplicate rows.
