# Unified entry image storage on R2

**Status: draft, awaiting review**

Unify how entry preview images (`ImageCrawler::EntryImage`, provider `entry_preview`) and
link preview images (`ImageCrawler::TwitterLinkImage`, provider `entry_link_preview`) are
processed, stored, referenced, and deleted. New writes go to Cloudflare R2 as WebP q65,
dual-written alongside the existing S3 path during the transition. Storage is
de-duplicated by original URL, reference-counted, and garbage-collected when entries are
deleted. Migration of existing entries is out of scope.

## Current state (verified)

Both flows already share one pipeline: `Pipeline::Find` → `Download` →
`Pipeline::Process` (vips, 542×304 jpg q80) → `Pipeline::Upload` (Fog/S3) → a
per-preset callback job that writes results onto the entry.

| | Entry preview | Link preview |
|---|---|---|
| Trigger | `Entry#find_images` after create | `HarvestLinks` (microposts/tweets) |
| Callback | `EntryImage#receive` | `TwitterLinkImage#receive` |
| Stored on entry | `entries.image` JSON: original_url, processed_url, width, height, placeholder_color | `entries.data`: `twitter_link_image_processed`, `twitter_link_image_placeholder_color` only |
| Object key | `public_id[0..2]/public_id.jpg` (per entry) | `…-twitter.jpg` (per entry) |
| Deleted by EntryDeleter | yes (`image["processed_url"]` → ImageDeleter) | **never — leaks forever** |

Cost problems in the current design:

1. **Duplicate objects.** `DownloadCache` (Redis, 1-week TTL, key = preset + SHA1(url))
   avoids re-downloading, but a cache hit still issues an S3 `COPY` and stores a *new
   per-entry object*. Storage grows linearly with entries even for identical images, and
   every hit is a billable copy request.
2. **Cache expiry.** After a week the same URL is fully re-downloaded and re-processed.
3. **Egress.** Images are served from S3 (host rewritten via `ENTRY_IMAGE_HOST`); R2 has
   zero egress cost via a custom domain.
4. **jpg q80** is larger than WebP q65 for equivalent perceived quality.
5. Link preview objects are never garbage-collected (see table above).

The half attempt: [app/models/image.rb](../../app/models/image.rb) exists with a
`provider` enum and fingerprint logic; its table was created in migration
`20240502090914` and **dropped** in `20250117094633`. `ImageCrawler::Image#send_to_feedbin`
has a commented-out `create_image` call. The model cannot be deleted outright — its enum
values are already serialized into Sidekiq payloads by `CacheRemoteFile`, `EntryImage`,
and `TwitterLinkImage`. It gets resurrected and extended instead.

## Data model

One `images` table; **one row per usage** (an entry holding an image), with the stored
object shared between rows via `url_fingerprint`. Refcount = number of rows with the
same fingerprint. This matches the half attempt's shape and keeps lookups to one query.

```ruby
create_table :images do |t|
  t.bigint :provider,          null: false   # existing enum on ::Image
  t.text   :provider_id,       null: false   # entry id
  t.bigint :feed_id                          # for the same-feed reuse rule
  t.text   :url,               null: false   # original image URL
  t.uuid   :url_fingerprint,   null: false   # MD5(url) — dedup + refcount key
  t.uuid   :image_fingerprint, null: false   # MD5 of processed bytes — content-level reuse checks
  t.text   :storage_path,      null: false   # R2 key, NOT a full URL (see "Serving")
  t.bigint :width,             null: false
  t.bigint :height,            null: false
  t.bigint :bytesize,          null: false
  t.text   :placeholder_color, null: false
  t.jsonb  :data,              null: false, default: {}   # preset, final_url, etc.
  t.timestamps
end
add_index :images, [:provider, :provider_id], unique: true
add_index :images, :url_fingerprint
add_index :images, [:feed_id, :image_fingerprint]
```

Differences from the 2024 attempt: adds `feed_id`, `bytesize`, and stores a
`storage_path` instead of `storage_url`.

The DB row is the canonical metadata source: **width, height, bytesize,
placeholder_color, provider** — consistent for both providers (link previews finally get
width/height/bytesize, which they lack today).

## Storage layout

- Bucket: new R2 bucket, public via custom domain (e.g. `images.feedbin.com`).
- Key: `url_fingerprint[0..2]/<url_fingerprint>.webp` — content-addressed by original
  URL, so existence is decidable from the DB alone and identical URLs share one object.
  All three entry presets (primary/twitter/youtube) output 542×304, so one object serves
  any provider; preset is recorded in `data` for debugging.
- Format: WebP, `saver(strip: true, quality: 65)`.
- Headers: explicit `Content-Type: image/webp` (today's upload sets none — R2 would
  serve `application/octet-stream`), `Cache-Control: max-age=315360000, public, immutable`.
  Drop `x-amz-acl` and `x-amz-storage-class`; R2 supports neither.
- Fog: R2 speaks S3 — a second `STORAGE_R2` config alongside `STORAGE`
  (`endpoint: https://<account>.r2.cloudflarestorage.com`, `region: "auto"`,
  `path_style: true`, R2 API token creds).

## Pipeline changes

### Find (dedup + reuse rules)

Candidate loop per URL, replacing the Redis positive cache with the DB:

1. **Dedup lookup**: `Image.find_by(url_fingerprint:)` (parameterized, per repo rules).
   Hit → skip download/process/upload entirely; run the reuse checks below; create this
   entry's usage row pointing at the same `storage_path`; fire the callback. No S3 COPY,
   no new object. The Redis *negative* cache ("attempted and failed", 1-month TTL) stays.
2. **Same-feed reuse rule** (meta-derived candidates only — see gap #7): reject the
   candidate if `Image.where(feed_id:).where(url_fingerprint:)` matches another entry;
   fall through to the next candidate. A second, content-level check by
   `image_fingerprint` runs post-process (below) to catch same-bytes-different-URL
   boilerplate. The entry's own existing row never blocks (idempotent re-runs; the
   `[provider, provider_id]` unique index plus `find_or_create` handles retries).
3. **Site-wide og:image rule**: when `MetaImages` resolves candidates for page P on host
   H, also resolve the og/twitter image of H's root page (`https://H/`), cached per host
   in Redis (~1 week TTL, "none" cached too, reusing the `MetaImagesCache` pattern).
   Filter out any candidate whose URL matches the root page's og:image. Skip the filter
   when P *is* the root page.

### Process

Crop once, save twice during the transition: jpg q80 (legacy S3 object, byte-identical
behavior to today) and WebP q65 (R2). Capture `bytesize` and `image_fingerprint` from
the WebP output in `Processor::Processed`.

Post-process content check: if the WebP's `image_fingerprint` already appears on another
entry of the same feed (meta-derived candidates only), reject and resume the candidate
loop — the existing `FindCritical` re-entry mechanism used for invalid images already
does exactly this.

### Upload (dual-write)

- PUT jpg → S3 exactly as today; legacy callback JSON (`entries.image` /
  `entries.data["twitter_link_image_*"]`) keeps pointing at the S3 URL.
- PUT WebP → R2 with the headers above; create/update the `::Image` row
  (the commented-out `create_image`, finished: feed_id, bytesize, storage_path,
  image_fingerprint, upsert keyed by `(provider, provider_id)`).
- The Redis positive `DownloadCache` is retired immediately for unified presets —
  the `images` table replaces it (permanent, and GC keeps it consistent). Only the
  negative "attempted, failed" cache stays in Redis. Non-unified presets
  (podcast/icon) keep the existing cache untouched.

### Callbacks

`send_to_feedbin` continues to update the legacy JSON for compatibility, and the Image
row becomes the canonical record. `TwitterLinkImage`'s `"#{public_id}-twitter"` id hack
stays at the job-routing layer only; the row is keyed properly by provider enum.

## Serving and read path

`Entry#processed_image` today rewrites the host of whatever URL sits in `entries.image`
to `ENTRY_IMAGE_HOST`. Mixing S3 and R2 absolute URLs through one rewrite breaks one or
the other — this is why the table stores `storage_path`, not a URL.

- New unified accessors: `Entry#preview_image` / `Entry#link_preview_image` (plus
  width/height/bytesize/placeholder_color) prefer the `Image` row — URL built as
  `R2_IMAGE_HOST + storage_path` — and fall back to the legacy JSON fields.
  `ENTRY_IMAGE_HOST` rewriting applies to the legacy fallback only.
- Cutover behind an env flag: until flipped, readers use legacy JSON (S3) even though
  rows exist; after flipping, Image rows win. Rollback = unset flag.
- Consumers to update: `EntryPresenter`, `entry_image_component.rb`,
  `_entry.html.erb` (link image), API v2 `_entry_extended.json.jbuilder` (`images.size_1`).

## Garbage collection

`EntryDeleter#prune_entries` currently plucks `image["processed_url"]` and enqueues
`ImageDeleter` (S3 object delete). New flow:

1. Keep the legacy pluck → `ImageDeleter` path for legacy per-entry S3 objects
   (including the dual-written jpg objects; they are per-entry, never shared).
2. Additionally enqueue `ImageGarbageCollector` with the deleted entry ids:
   - Load `Image.where(provider: [entry_preview, entry_link_preview], provider_id: ids)`.
   - Group by `url_fingerprint`. For each fingerprint, inside a transaction holding
     a `pg_advisory_xact_lock` on the fingerprint: delete the usage rows, re-check
     `Image.where(url_fingerprint:).exists?`, and if none remain delete the R2 object.
   - No Redis invalidation is needed for unified images: the positive `DownloadCache`
     is never written for them (the `images` table replaces it from day one), so there
     are no cache keys to go stale. Only the negative "attempted, failed" keys stay in
     Redis, and those reference nothing.
   - `Pipeline::Find`'s dedup-hit insert takes the same advisory lock, closing the race
     where a new entry adopts an object mid-GC.
3. This also fixes the existing leak: link preview images become deletable for the first
   time.

Starred entries are never pruned, so their refcounts never reach zero — correct, their
images must live on.

**Known residual race, accepted:** `Upload`'s R2 `PUT` happens *before* `create_image`
takes the advisory lock (Task 6). If GC deletes that same fingerprint's last old row and
object in the window between the fresh `PUT` and `create_image` acquiring the lock, the
fresh object is deleted and the new row (inserted once GC releases the lock) ends up
pointing at nothing. The window is milliseconds and requires the same URL to be
simultaneously re-crawled and last-pruned — negligible frequency. This does not self-heal:
`find_images` only runs on entry create, and `FixImage` checks the per-entry legacy S3 jpg,
which still exists and is unaffected. The affected entry keeps serving its legacy S3 image
during the transition; recovery is manual.

## Cleanup of the half attempt

- Keep `app/models/image.rb`; update the schema comment; add `feed_id`/`bytesize`/
  `storage_path`; keep the provider enum values stable (they're in queued payloads).
- New migration recreating the table (supersedes the dropped 2024 one).
- Make `ImageCrawler::Image#initialize` *ignore* unknown attributes instead of raising.
  `Process`/`Upload` run on host-local queues (`local_queue` = `name_<hostname>`) on
  crawler machines; deploys are not atomic across hosts and every pipeline job is
  `retry: false`, so a payload attribute mismatch during deploy silently drops images
  today. Loosen first, deploy everywhere, then start emitting new attributes
  (`feed_id`, `bytesize`, `storage_path`).

## Rollout phases

- **Phase 0 — infra + schema.** R2 bucket, custom domain, API token; `STORAGE_R2`
  initializer + env vars; images migration; tolerant `Image#initialize` deployed fleet-wide.
- **Phase 1 — shadow writes.** Dual save/PUT; Image rows created; reuse rules active
  (always on — no flag; they only apply to unified presets, so `R2_BUCKET_IMAGES` is
  the effective gate). Serving unchanged. Verify row/object counts, dedup hit rate,
  R2 error rate (Librato counters: `image.dedupe_hit`, `image.r2_upload`, `image.r2_error`,
  `image.reuse_skipped`, `image.reuse_rejected`, `image.gc_rows`, `image.gc_objects`).
- **Phase 2 — read cutover.** Flip the read flag; new-system entries serve WebP from R2.
  Watch client behavior/API consumers.
- **Phase 3 — retire legacy writes.** Stop jpg save + S3 PUT; retire the Redis positive
  download cache; GC becomes purely refcount-based for new images. Legacy S3 deletion in
  EntryDeleter stays until the (out-of-scope) backfill migration of old entries.

## Testing

Existing coverage to extend: `test/jobs/image_crawler/*` (entry_image, twitter_link_image,
download_cache, pipeline, processor) and `entry_deleter_test.rb`. New tests (TDD):

- dedup hit creates a usage row and skips download/upload
- same-feed URL reuse rejected pre-download; same-feed fingerprint reuse rejected
  post-process; next candidate attempted via FindCritical
- site-wide og:image filtered (root cached, "none" cached, root page itself exempt)
- upload writes both stores, correct R2 headers/Content-Type, Image row complete
  (width/height/bytesize/color/provider)
- GC: refcount respected across feeds, last-reference deletes object + Redis key,
  advisory-lock race (insert during GC) safe, link previews cleaned
- read path: row preferred, JSON fallback, ENTRY_IMAGE_HOST only on fallback
- webp output at q65, strip

## Gap analysis (answers to "what am I missing?")

1. **Link preview images are never deleted today.** `EntryDeleter` only reads
   `entries.image`; every `…-twitter.jpg` object leaks. The plan fixes it forward, but the
   *already-leaked* S3 objects are a separate one-off sweep (cheap win, not entry-migration).
2. **`ENTRY_IMAGE_HOST` conflicts with mixed-host URLs.** Rewriting hosts on read breaks
   as soon as two generations of URLs coexist. Solved by storing `storage_path` + a
   per-generation host, but it must be designed in from the start.
3. **Content-Type has never been set on upload.** S3+jpg got away with it; R2+WebP will
   serve `application/octet-stream` and some clients will refuse to render it.
4. **R2 header differences.** No ACLs, no storage classes — the current
   `storage_options` would need to be split per store.
5. **GC insert/delete race.** Between "no rows left" and "object deleted", a new entry can
   adopt the object. Advisory lock per fingerprint (shared by GC and the dedup-hit insert).
6. **Deploy-ordering hazard.** Strict payload validation + host-local queues + retry:false
   means new job attributes brick in-flight jobs mid-deploy. Loosen the initializer first.
7. **Feed-reuse rule needs scoping.** Applied to *all* candidates it would block legitimate
   repeats — the same image in a retweet chain, repeated inline images in microposts.
   Restrict it to meta-derived candidates (og:image/twitter:image and page-fetch results),
   where boilerplate lives.
8. **First-entry problem.** The root-page check only catches boilerplate that also appears
   on the root page. A feed whose generic image is some CDN placeholder not on the
   homepage still hands it to the *first* entry; only subsequent entries are protected by
   the reuse rule. A frequency heuristic (retroactively demote images used by ≥N entries)
   is a possible future pass — YAGNI now.
9. **URL-keyed dedup can go stale.** A URL like `/latest.jpg` can serve different bytes
   later; dedup will pin the first version forever (today's cache expires weekly, hiding
   this). Accepted trade-off; if it bites, add a re-validation age to the dedup lookup.
10. **WebP reaches API consumers.** `images.size_1.cdn_url` in API v2 will return `.webp`
    to third-party clients and the native apps. Fine for anything modern (iOS 14+, all
    current browsers), but it's an externally visible change worth a release note.
11. **Scope boundary with the other presets.** podcast/itunes, icon, and remote-file
    presets ride the same pipeline and other buckets (`preset.bucket`). They stay on
    their current storage in this phase — pipeline changes must keep the preset-bucket
    branch working. Unifying them onto R2 is a natural follow-up.
12. **`FixImage` is hardcoded to `s3.amazonaws.com`** (HTTP pool + HEAD checks). It needs
    to learn R2 or be retired once refcounted GC makes "object missing" a bug signal
    rather than routine.
13. **`Entry#processed_image?` gates re-crawling** off the legacy JSON. During transition
    the JSON keeps being written so the guard holds; when legacy writes stop, the guard
    must consult the Image row or entries will re-crawl on every save.
14. **Redis download-cache invalidation** (you called this out) — handled in GC during
    transition; the positive cache is retired entirely at Phase 3, which removes the
    stale-pointer class of bugs rather than managing it.
15. **Table growth.** One row per entry-with-image; at Feedbin entry-retention scale this
    is millions of rows but with narrow indexes — fine on Postgres, worth watching
    autovacuum on the delete-heavy workload (GC deletes in feed-sized batches).
16. **Metrics.** Dedup hit rate, bytes stored, GC deletions, R2 errors — needed both for
    verifying the cost savings and for alerting during cutover.
17. **Backfill anticipation** (out of scope, but shaped now): `storage_path` +
    text `provider_id` + provider enum mean the eventual migration is "process old
    entries through the same pipeline", no schema rework.
