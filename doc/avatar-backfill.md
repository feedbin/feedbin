# Avatar backfill

Deploy the `micropost_avatar` and `icon` image presets, `ImageCrawler::MicropostAvatar`,
`BackfillAvatarCopies`, and `BackfillMicropostAvatars` together (Deploy A of
the avatar images cutover), then run these production Rails console
commands in order: the copy first, then the micropost pass.

`BackfillAvatarCopies` copies every avatar the icon proxy already cached in
`remote_files` into an `images` row on the `remote_file` provider, keyed by
the url's fingerprint, re-encoding each legacy object to the `icon`
preset's 200px png as it goes. It runs first because it never re-requests a
source: production holds 2,394,516 `remote_files` rows, most of them
Twitter's and dead, so a copy that talks only to the legacy bucket and the
unified store is the only way to move that many rows without hammering
third-party hosts or a live crawl's rate limits. It fans out on the
`backfill` queue in batches of `BackfillAvatarCopies::BATCH_SIZE` (250)
ids, with no spread — about 9,600 batches for 2.4 million rows. The wall
clock is batches ÷ the number of Sidekiq threads working the `backfill`
queue, so watch the batch log rather than expect a fixed ETA.

`BackfillMicropostAvatars` runs second, after the copy's queue has
drained, and walks every micropost feed with an entry lacking an
`entry_icon` row, re-running `ImageCrawler::MicropostAvatar.schedule` for
it off the critical queues. Because the copy already ran, most avatar urls
now resolve to a `remote_file` row the crawler can attach with no request;
only an avatar the copy missed — a legacy object the proxy never cached,
or one genuinely new since the copy started — costs a download. It fans
out in the `SidekiqHelper` style, one job per `SidekiqHelper::BATCH_SIZE`
feed ids on the `utility` queue, with `at` timestamps spread over
`BackfillMicropostAvatars::SPREAD` (one hour by default) so the downloads
that remain share the crawl queues' rate limits with live crawling, not
all at once.

## Pre-deploy checks

```ruby
puts "remote_files rows: #{RemoteFile.count}"
puts "remote_files rows with no images row (the copy's set): #{BackfillAvatarCopies.pending.count}"
puts "micropost feeds with an entry lacking a row (the pass's set): #{BackfillMicropostAvatars.pending.count}"
puts "unlabeled podcast art rows (must be 0): #{Image.provider_entry_icon.where(Image.data_projection("preset").eq("podcast")).where.not(kind: :cover_art).count}"
puts "YouTube channels with no avatar row: #{Embed.youtube_channel.where.missing(:channel_image).count}"
```

These are the two jobs' starting sets. Expect `remote_files rows` near
2,394,516 and the copy's pending count close to it; the pass's pending
count is unrelated to the copy's and does not need to match either one.
`Entry#itunes_image` now reads the row's kind, so an unlabeled podcast art
row would drop an episode's own art. Those YouTube channels show the
proxied thumbnail on their card until `BackfillChannelImages` covers them.

## Trial

The batch that holds the lowest pending remote file id, run inline:

```ruby
remote_id = BackfillAvatarCopies.pending.order(:id).limit(1).pluck(:id).first
batch = ((remote_id - 1) / BackfillAvatarCopies::BATCH_SIZE) + 1
puts "first pending remote file: #{remote_id}, batch: #{batch}"
before = BackfillAvatarCopies.batch_scope(batch).count
puts "rows in that batch: #{before}"
BackfillAvatarCopies.new.perform(batch)
puts "copied in that batch (rows now present): #{before - BackfillAvatarCopies.batch_scope(batch).count}"
```

A dead source is expected and is not a failure: `Copy#call` logs it and
leaves the row pending rather than raising, so `copied in that batch` will
usually read under 250. A storage or database error is different — see
Watching the copy, below.

## Full run

```ruby
BackfillAvatarCopies.perform_async(nil, true)
```

`schedule` pushes one job per batch, from the table's own first batch
through its last, all onto the `backfill` queue at once — no spread, since
the copy talks to storage, not a third party.

To continue after an interruption, resume from the batch number on the
last `BackfillAvatarCopies: batch=` log line before the stop:

```ruby
# The lowest remaining pending id's batch: reruns are safe (a copied row
# leaves pending), so resuming one batch behind the last log line costs
# nothing and needs no number copied by hand from the log.
from_batch = ((BackfillAvatarCopies.pending.minimum(:id) - 1) / BackfillAvatarCopies::BATCH_SIZE) + 1
puts "resuming the copy from batch: #{from_batch}"
BackfillAvatarCopies.perform_async(nil, true, from_batch)
```

## Watching it

Each batch logs a line:

```
BackfillAvatarCopies: batch=... scanned=... copied=... skipped=...
```

Skipped rows are not a failure: a dead legacy object or an undecodable
image stays pending forever and cannot be copied. `Copy::STORE_ERRORS`
re-raises a storage or database error instead of logging it as skipped, so
Sidekiq retries the whole batch — if the queue depth below is not
draining, check the retry set for this class before assuming every row is
simply dead. Check row counts and the queue depth, ideally twice a day
apart so the trend is visible:

```ruby
puts "copy pending: #{BackfillAvatarCopies.pending.count}"
puts "remote_file rows: #{Image.provider_remote_file.count}"
puts "backfill queue depth: #{Sidekiq::Queue.new("backfill").size}"
```

## The micropost pass

Run this only once the copy's queue is empty (`backfill queue depth: 0`
above): most of the pass's downloads are avoided only because the rows the
copy wrote are already there to attach.

A trial batch, in the same shape as the copy's:

```ruby
feed_id = BackfillMicropostAvatars.pending.order(:id).limit(1).pluck(:id).first
batch = ((feed_id - 1) / SidekiqHelper::BATCH_SIZE) + 1
puts "first pending feed: #{feed_id}, batch: #{batch}"
puts "pending feeds in that batch: #{BackfillMicropostAvatars.batch_scope(batch).count}"
BackfillMicropostAvatars.new.perform(batch)
puts "attached and scheduled: see the BackfillMicropostAvatars log line above"
```

The full run:

```ruby
BackfillMicropostAvatars.perform_async(nil, true)
```

Watching it:

```ruby
puts "pass pending: #{BackfillMicropostAvatars.pending.count}"
puts "entry_icon avatar rows: #{Image.provider_entry_icon.where(kind: :avatar).count}"
puts "MicropostAvatar retries (must be 0): #{Sidekiq::RetrySet.new.count { it.klass == "ImageCrawler::MicropostAvatar" }}"
```

`MicropostAvatar` sets `retry: false`, so that count should always read 0;
a nonzero count means something upstream re-enqueued through a retrying
path and is worth investigating on its own.

`BackfillMicropostAvatars.pending` is prefiltered by the parser's own
marker for a micropost feed, so a zero there does not mean every micropost
feed's entries are covered — an unmarked feed is picked up on its own the
next time it crawls with new posts.

## The gate before Deploy B

Both pending counts — `BackfillAvatarCopies.pending.count` and
`BackfillMicropostAvatars.pending.count`, read the same way as in Watching
it and the micropost pass's own watch above — must hold steady across two
checks a day apart before Deploy B (the proxy's retirement) can proceed.

List what the copy has left:

```ruby
residual = BackfillAvatarCopies.pending.order(:id).limit(50).pluck(:id, :original_url)
puts "copy residual total: #{BackfillAvatarCopies.pending.count}"
residual.each { |id, url| puts "  #{id} #{url}" }
```

And confirm in the browser: the sidebar, an entry list with microposts, an
entry list with stored tweets, a micropost entry view, and a YouTube embed
card show no `/files/icons/` url except the accepted residual above, and
`image.unified_error` is flat.

Fragments cached during Deploy A for tweet entries, Twitter feed icons, and
embed cards can still carry a `/files/icons/` url even once both pending
counts read 0: their cache keys do not digest the copied rows, only the
row-backed sources, so a fragment written before a row landed keeps
rendering the proxy until something else invalidates it. That is expected
and is not part of the residual above. Deploy B must bump `entries_helper`'s
cache key from `"v15"` to `"v16"` and both of `feeds_helper`'s version
strings when it removes the proxy, so every cached fragment is forced to
re-render against the rows.

**Deploy B deletion list** — dead once the proxy retires: `CacheRemoteFile.schedule`
(no callers), `Pipeline::Find#attempt_legacy` and `DownloadCache.copy` (no
preset reaches them), and the `RemoteFile.signed_url` fallbacks marked
`# Deploy A only`.

## Residual avatars

A residual left after Deploy B is not broken, it degrades: a micropost
with no row renders the feed's icon in the list and the default avatar in
the view; a tweet with no row renders the default avatar; an embed card
renders the source's own icon. Reruns of either job are safe: a copied or
attached row leaves `pending`, and both `Image.attach!` and the copy's
`create_image` upsert onto a content-addressed path, so scheduling either
backfill twice while it is in flight does not create duplicate rows.
