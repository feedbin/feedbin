# Deploy checklist: API v3

Two deploys. **Step one** is branch `api-v3-migrations`: the seven migrations and `structure.sql`, nothing else. It runs under today's code. **Step two** is branch `api-v3-oauth`: the code, once every migration has finished.

Today's code works on the new schema. The new tables are unused, the new `entries` columns have a default or allow null, and every `unreads` query by `user_id` can use a composite index. The step-one branch passes main's test suite on the new schema.

## Step one: schema

**Build the slow parts by hand before deploying.** `cap deploy` runs `db:migrate` on app4 before it publishes the release, and it pauses every Sidekiq process (`deploy:quiet`) from the start of the deploy until the restart at the end. Three of these migrations build an index over all of `entries` or `unreads`, which together take an hour or more. Left to the deploy, that is an hour or more with no background jobs, on a build that dies with your SSH session and is cancelled by the one-hour statement timeout. Built by hand first, the deploy's migrations find everything in place and finish in seconds.

The migrations, in the order they run:

| Migration | What it does | By hand first | In the deploy |
| --- | --- | --- | --- |
| `create_doorkeeper_tables` | New tables | | Instant |
| `add_revision_to_entries` | Two columns on `entries`, then an index on `(edited_at, id)` where `edited_at` is set. The index is empty, but building it reads all of `entries` twice. | **Yes** | Skips what exists |
| `add_unreads_user_entry_created_at_index` | An index on `unreads` | **Yes** | Skips what exists |
| `remove_unreads_user_id_index` | A concurrent drop | | Short |
| `create_entry_videos` | A new table. Its foreign key takes a brief lock on `entries`; the table is empty, so nothing is checked. | | Instant |
| `add_feed_id_created_at_id_index_to_entries` | An index on `entries (feed_id, created_at, id)`, about 7 GB at 160M entries | **Yes** | Skips what exists |
| `create_oauth_application_profiles` | A new table. Its foreign key is to `oauth_applications`, which is new and empty. | | Instant |

### How long the builds take

These are estimates, not measurements. A concurrent build reads its table twice, and for `entries` that read is nearly all of the time, so the heap's size decides it:

```sql
SELECT relname, pg_size_pretty(pg_relation_size(oid)) AS heap, reltuples::bigint AS rows
FROM pg_class WHERE relname IN ('entries', 'unreads');
```

One read of `entries` takes about its heap size divided by the read rate: at 200 MB/s, 8 minutes for 100 GB and 25 minutes for 300 GB. Production traffic slows it.

| Build | Work | Estimate |
| --- | --- | --- |
| `index_entries_on_edited_at_and_id` | Two reads of `entries`; nothing to sort | 15–60 min |
| `index_unreads_on_user_id_and_entry_created_at_and_entry_id` | Two reads of `unreads` and a sort | 5–20 min |
| `index_entries_on_feed_id_and_created_at_and_id` | Two reads of `entries`, a sort of every row, and the index written | 25–90 min |

### Build by hand

- [ ] **Start when nothing long is running:** no backfill, export, or `renderings:rebuild` pass. Before it finishes, a concurrent build waits for every transaction that started before it. To check:

```sql
SELECT pid, now() - xact_start AS age, state, left(query, 80)
FROM pg_stat_activity
WHERE xact_start < now() - interval '10 seconds'
ORDER BY xact_start;
```

- [ ] **Open a database console that survives your connection.** On app4, in `tmux`:

```bash
cd /usr/local/srv/apps/feedbin/current && bin/rails dbconsole -p
```

- [ ] **Add the columns.** Each `ALTER` needs a brief exclusive lock on `entries` and changes the table definition only; it rewrites no rows (Postgres 11+). With the 10 s lock timeout, one that cannot get its lock fails rather than stall the site. Run it again if it does.

```sql
SET statement_timeout = 0;
SET lock_timeout = '10s';
ALTER TABLE entries ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1;
ALTER TABLE entries ADD COLUMN IF NOT EXISTS edited_at timestamp(6) without time zone;
```

- [ ] **Build the indexes,** one statement at a time. A concurrent build blocks no reads or writes, and it waits on old transactions without holding anyone else up, so the lock timeout comes off.

```sql
SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE INDEX CONCURRENTLY IF NOT EXISTS index_entries_on_edited_at_and_id
  ON entries (edited_at, id) WHERE edited_at IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS index_unreads_on_user_id_and_entry_created_at_and_entry_id
  ON unreads (user_id, entry_created_at, entry_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS index_entries_on_feed_id_and_created_at_and_id
  ON entries (feed_id, created_at, id);
```

- [ ] **Watch a build from a second console.** Postgres 11 has no progress view for index builds (`pg_stat_progress_create_index` arrived in 12), so watch the statement and the index's size. The `(edited_at, id)` index stays near empty; the other two grow in the second half of the build.

```sql
SELECT pid, now() - query_start AS running, wait_event_type, wait_event, left(query, 70)
FROM pg_stat_activity WHERE query ILIKE 'create index concurrently%';

SELECT pg_size_pretty(pg_relation_size('index_entries_on_feed_id_and_created_at_and_id'));
```

- [ ] **Confirm no index is invalid.** This must return no rows. `IF NOT EXISTS` skips an invalid index a failed build left behind, so check after every build:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

If one is listed, drop it and build it again:

```sql
DROP INDEX CONCURRENTLY IF EXISTS index_entries_on_feed_id_and_created_at_and_id;  -- the one listed
```

- [ ] **Refresh the statistics.**

```sql
ANALYZE entries;
ANALYZE unreads;
```

### Deploy

- [ ] **Merge `api-v3-migrations` into main and `cap deploy`.** The migrations run inside the deploy, with the usual 10 s lock timeout and one-hour statement timeout. With the columns and indexes already there, what is left is new tables, one concurrent index drop, and an `ANALYZE` after each index migration.
- [ ] **If the deploy's migration step fails,** nothing is half-built: run the deploy again. Every migration is safe to run again. The two that create tables and the one that creates the profiles table run in a transaction, and the three index migrations skip what exists and rebuild an index a failed build left invalid.

### After

- [ ] **Confirm everything ran.** `bin/rails db:migrate:status` shows all seven migrations as `up`.
- [ ] **Confirm no index is invalid,** with the query above.
- [ ] **Watch `unreads` query times** for the next day. `index_unreads_on_user_id` is gone, and the composite indexes that start with `user_id` cover its queries.

### If you skip the build by hand

The migrations still do everything themselves. Expect the deploy to block and Sidekiq to stay paused until they finish, keep the SSH session alive, and raise `StrongMigrations.statement_timeout` in `config/initializers/strong_migrations.rb` above the longest build first: at one hour, a build that runs over is cancelled and leaves an invalid index. The `DB_STATEMENT_TIMEOUT=60min` the deploy sets does not help, because the initializer's value is applied when a migration starts.

## Step two: code

- [ ] **Bring main into `api-v3-oauth`.** The migration files and `structure.sql` are the same on both branches, so they merge cleanly. Run `bin/rails test`.
- [ ] **Deploy web and Sidekiq together.**
- [ ] **API v3 is off for everyone** until you turn it on for each user. That flag covers the settings page, OAuth authorization and the API itself. To try it yourself:

```ruby
User.find_by!(email: "you@example.com").setting_on!(:api_v3)
```

- [ ] **Mark Feedbin's own apps as first-party** as soon as they are created, before anyone signs in with them, so their tokens get the `account` scope. Without it an app cannot read or change the account (`/v3/account`), register a device, record a purchase or list tokens. The task also upgrades the app's existing tokens, the ones created in settings included:

```bash
bin/rails "api_v3:first_party[<application uid>]"
```

- [ ] **Expect the crawler to start counting edits.** `revision` goes up and `edited_at` is set whenever an entry changes. `index_entries_on_edited_at_and_id` grows only as edits come in.

### Rollback

- [ ] **Revert the code and leave the schema.** Step one already ran today's code on it.
