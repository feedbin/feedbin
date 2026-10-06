# Newsletter pages move from S3 to B2

Date: 2026-10-05
Status: approved 2026-10-05

## Goal

Store every newsletter page on Backblaze B2. Today `NewsletterSaver` stores them on S3.
Serve each page as gzip with headers that tell the browser the body is gzip.
Move all existing newsletter pages with a backfill.

## What exists today

- `NewsletterSaver` builds an HTML document from `entry.content`.
- It gzips the document with `ActiveSupport::Gzip.compress`.
- It puts the object in `AWS_S3_BUCKET_NEWSLETTERS`. The key is `<public_id[0..2]>/<public_id>.html`.
- It sets these headers on the object:
  - `Content-Type: text/html; charset=utf-8`
  - `Content-Encoding: gzip`
  - `Cache-Control: max-age=315360000, public`
  - `Expires`, `x-amz-acl: public-read`, and `x-amz-storage-class`
- It builds the entry URL from `ENV["NEWSLETTER_HOST"]` and `response.data[:path]`. It saves the URL in `entry.url`.
- `Entry#newsletter_url` builds the same URL from `public_id`. `EntriesController#newsletter` redirects to it when `NEWSLETTER_HOST` is set.
- In production, `NEWSLETTER_HOST` is a CDN or proxy hostname in front of S3.
- The image store already uses B2 through the S3 API. See `STORAGE_IMAGES` in `config/initializers/s3.rb` and the `UNIFIED_*` variables.

**Gzip is already in place.** This project keeps it. It makes sure that B2 and the CDN serve it correctly.

## Decisions

1. **Rebuild each page from `entry.content`. Do not copy from S3.**
   The saver needs only the entry row. The backfill therefore does not read the old bucket.
   A rebuilt page can differ a little from the old page. The reason is that `build_document` changed over time. The new page uses the current format. This is acceptable.
2. **Keep `NEWSLETTER_HOST` and keep the key format.**
   The URL in `entry.url` does not change. The backfill does not rewrite `entry.url`.
   The cutover is one change: the CDN origin moves from S3 to B2.
3. **Build the URL from the key, not from the storage response.**
   With path-style access, `response.data[:path]` includes the bucket name. The bucket name must not appear in the public URL.
   `NewsletterPage#url` returns the same string as `Entry#newsletter_url`.
4. **Write to both stores until the cutover.**
   New newsletters arrive all the time. The CDN reads from S3 until the origin moves.
   If the saver wrote only to B2, each new newsletter would give a 404 until the cutover.
   The saver therefore writes to S3 first, then to B2, while the legacy S3 config is present.
   A B2 failure then raises and retries, and the page is already on S3 where the CDN reads it.
5. **Reuse the `UNIFIED_*` account, key, and endpoint.** Only one variable is new: `NEWSLETTERS_BUCKET`.
   The B2 application key must have access to the new bucket.
6. **Store gzip only. Serve gzip always.**
   B2 does not decompress. Every current browser sends `Accept-Encoding: gzip`. There is no plain variant.
7. **Drop the S3-only headers on B2.** Do not send `x-amz-acl` or `x-amz-storage-class`.
   B2 sets visibility on the bucket. The bucket must be public, or the CDN must hold a read key.
   The probe in Step 1 of the rollout confirms this.

## Components

### `NewsletterPage` (new, `app/models/newsletter_page.rb`)

One job: turn an entry into a stored page.

- `NewsletterPage.new(entry)`.
- `#key` returns `"#{public_id[0..2]}/#{public_id}.html"`.
- `#document` holds the logic that moves out of `NewsletterSaver`: `build_document`, `document_title`, `text_email_css`.
- `#body` returns the gzipped document.
- `#headers` returns the object headers: `Content-Type`, `Content-Encoding`, `Cache-Control`.
  The `Cache-Control` value stays `max-age=315360000, public`. The page never changes at its key.
- `#url` returns the public URL, built from `NEWSLETTER_HOST` and `#key`. It returns `nil` when `NEWSLETTER_HOST` is unset.
- `#save` puts the object on B2. It returns `#url`.

`Entry#newsletter_url` calls `NewsletterPage#url`. This gives one definition of the URL.

### `NewsletterSaver` (changed)

- `perform` calls `NewsletterPage.new(entry).save`.
- It writes `entry.url` only when `#url` is present and differs from the current value.
- While `AWS_S3_BUCKET_NEWSLETTERS` is set, `perform` also puts the same body and headers on S3. This is the dual write.
  The old S3 headers (`x-amz-acl`, storage class, `Expires`) stay on that call only.

Behavior change: with `NEWSLETTER_HOST` unset, the saver no longer overwrites `entry.url` with a raw storage host.
The receiver sets `entry.url` to the local `newsletter_entry_url`. That route renders the page itself, so development works without a CDN.

### Storage config

- Add no new storage hash. `NewsletterPage` uses `STORAGE_IMAGES`, which reads the `UNIFIED_*` variables.
- Add `NEWSLETTERS_BUCKET` to `.env.example`.
- Do not add a boot check. The saver runs in Sidekiq, and a missing bucket raises on the first job.
  A boot failure would take the web process down for a worker setting.

### `NewsletterBackfill` (new, `app/jobs/newsletter_backfill.rb`)

It follows `BackfillGuid` and the rule in the project notes: backfills are Sidekiq jobs, not rake tasks.

- `build` enqueues one job for each feed in `Feed.newsletter`.
- `perform(feed_id)` reads the feed's entries with `find_in_batches(batch_size: 500)`.
  For each entry it calls `NewsletterPage.new(entry).save` against B2 only.
- A put that fails raises. Sidekiq retries the feed job. A retry is safe, because a put overwrites the same key with the same body.
- The job skips an entry whose `content` is `nil`. It counts these entries so the operator can see them.
- It runs on the `utility` queue.
- Redis pass counters track progress, and a `.progress` method reports them.
  A full-table count times out under the production 15 s `statement_timeout`. The counters avoid it.

## Serving

B2 stores `Content-Encoding` and `Cache-Control` with the object. It returns them on every GET.
The CDN must pass both headers through and must not decompress the body.

The acceptance check for the serving path is one request through the CDN host:

```
curl -sI -H 'Accept-Encoding: gzip' https://$NEWSLETTER_HOST/<key>
```

The response must show `content-encoding: gzip`, `content-type: text/html; charset=utf-8`, and the long `cache-control`.
The same URL with `curl --compressed` must print readable HTML.

The CDN origin must reach the B2 object at the S3-style path `/<bucket>/<key>`, or at the virtual-host form.
The origin rule maps the public path `/<key>` to that origin path. This is a CDN setting, not a code change.

## Rollout

Each step is a production step and goes in the runbook (`docs/ops/newsletter-b2-runbook.html`).
The plan phase writes the runbook.

1. **Probe.** Put one gzip object on B2 with the saver headers. Read it through the B2 endpoint.
   Confirm that the response carries `Content-Encoding: gzip` and the long `Cache-Control`. Confirm that the bucket serves it without a key.
2. **Deploy A.** Create the B2 bucket and set `UNIFIED_BUCKET_NEWSLETTERS`. Deploy the dual-write saver.
3. **Backfill.** Run `NewsletterBackfill.new.build`. Watch `.progress` until it reaches the total.
4. **Catch up.** Run `NewsletterBackfill.new.build` a second time. This covers any save that failed during the first pass.
5. **Spot check.** Request three old pages and one new page from B2 and check the headers.
6. **Cutover.** Move the CDN origin from S3 to B2. Run the acceptance check on the public host.
7. **Deploy B.** The migration is complete when the public acceptance check passes. Deploy B right after it.
   Deploy B removes the S3 write and the `AWS_S3_BUCKET_NEWSLETTERS` setting. Keep the S3 objects. A rollback is one origin change, and the objects stay until the S3 bucket is retired.
8. **Retire S3.** Delete the old bucket when you no longer need the rollback.

## Testing

- `NewsletterPage`: key, URL with and without `NEWSLETTER_HOST`, path-style endpoint (no bucket in the URL),
  body round trip through `ActiveSupport::Gzip.decompress`, header values, title fallback, text format, deep nesting.
  These cases move from `test/jobs/newsletter_saver_test.rb`.
- `NewsletterSaver`: B2 put carries the three headers and no `x-amz-*` headers. The S3 put happens only while the legacy bucket is set.
  `entry.url` stays the same when it already equals the page URL.
- `NewsletterBackfill`: it enqueues only newsletter feeds. It puts one object for each entry. It skips an entry with no content.
  A second run puts the same keys and changes no row.
- `Entry#newsletter_url` returns the value of `NewsletterPage#url`.

Tests stub the B2 endpoint with WebMock. They run with `bundle exec rake`.

## Out of scope

- Copying old objects from S3. The rebuild replaces it.
- Deleting the S3 objects. Retiring the bucket removes them.
- A non-gzip variant of the page.
- Changes to `EntriesController#newsletter` or to the development rendering path.

## Open items for review

None. The review settled the key set (reuse `UNIFIED_*`), the bucket (public), and the soak (none).
