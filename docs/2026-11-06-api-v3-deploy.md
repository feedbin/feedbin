# Deploy checklist: API v3

Two deploys. **Step one** is branch `api-v3-migrations`: the five migrations and `structure.sql`, nothing else. It runs under today's code. **Step two** is branch `api-v3-oauth`: the code, once every migration has finished.

Today's code works on the new schema. The new tables are unused, the new `entries` columns have a default or allow null, and every `unreads` query by `user_id` can use a composite index. The step-one branch passes main's test suite on the new schema.

## Step one: schema

The migrations, in the order they run:

| Migration | Locks | Time |
| --- | --- | --- |
| `create_doorkeeper_tables` | New tables only | Instant |
| `add_revision_to_entries` | `entries`, briefly, to add two columns. It changes the table definition only and rewrites no rows (Postgres 11+). Then a concurrent index build, which does not block reads or writes. | **Long:** the index scans all of `entries` twice |
| `add_unreads_user_entry_created_at_index` | A concurrent index build | **Long:** scans all of `unreads` |
| `remove_unreads_user_id_index` | A concurrent drop | Short |
| `create_entry_videos` | `entries`, briefly, while the new table's foreign key is added. The new table is empty, so nothing is checked. | Instant |

### Before

- [ ] **Raise the statement timeout.** `config/initializers/strong_migrations.rb` sets `StrongMigrations.statement_timeout = 1.hour` for the whole migration connection, and that includes the concurrent index builds. Set it above your longest expected build, for this deploy only. To size it, check the tables:

```sql
SELECT relname, pg_size_pretty(pg_relation_size(oid)) AS heap, reltuples::bigint AS rows
FROM pg_class WHERE relname IN ('entries', 'unreads');
```

- [ ] **Know what the 10 s lock timeout does.** `StrongMigrations.lock_timeout = 10.seconds` also applies here:
  - **The `ALTER`s fail fast.** Adding the columns and the foreign key each need a brief exclusive lock on `entries`. If one waits more than 10 s, it fails rather than stall the site. Up to then, queries on `entries` queue behind it.
  - **A long transaction can fail an index build.** Before it finishes, a concurrent build waits for every transaction that started before it. A transaction open longer than 10 s at that point fails the build, which leaves an invalid index behind (see "If a migration fails").
- [ ] **Start when nothing long is running:** no backfill, export, or `renderings:rebuild` pass. To check:

```sql
SELECT pid, now() - xact_start AS age, state, left(query, 80)
FROM pg_stat_activity
WHERE xact_start < now() - interval '10 seconds'
ORDER BY xact_start;
```

- [ ] **Optional: build the `unreads` index ahead of time, by hand.** Its migration skips an index that already exists and is valid, so building it first takes it out of the deploy. Don't do this for the `entries` index: its migration has no `if_not_exists` and fails if the index exists.

```sql
SET statement_timeout = 0;
SET lock_timeout = 0;
CREATE INDEX CONCURRENTLY IF NOT EXISTS index_unreads_on_user_id_and_entry_created_at_and_entry_id
  ON unreads (user_id, entry_created_at, entry_id);
```

### Deploy

- [ ] **Merge `api-v3-migrations` into main, deploy it, and run the migrations.**
- [ ] **Watch the index builds.** In the second phase, `blocks_done` counts up to `blocks_total`:

```sql
SELECT p.pid, c.relname AS index, p.phase, p.blocks_done, p.blocks_total, p.tuples_done, p.tuples_total
FROM pg_stat_progress_create_index p JOIN pg_class c ON c.oid = p.index_relid;
```

### After

- [ ] **Confirm everything ran.** `bin/rails db:migrate:status` shows all five migrations as `up`.
- [ ] **Confirm no index is invalid.** This must return no rows:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

- [ ] **Watch `unreads` query times** for the next day. `index_unreads_on_user_id` is gone, and the composite indexes that start with `user_id` cover its queries.
- [ ] **Put `statement_timeout` back to `1.hour`.**

### If a migration fails

Each one is safe to run again except `add_revision_to_entries`.

- **`create_doorkeeper_tables`, `create_entry_videos`:** each runs in a transaction, so a failure leaves nothing behind. Run the migrations again.
- **`add_unreads_user_entry_created_at_index`:** run it again. It drops an invalid index left by a failed build, then builds the index again.
- **`remove_unreads_user_id_index`:** run it again.
- **`add_revision_to_entries`:** it runs without a transaction, so whatever finished before the failure stays. Find out what that was:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'entries' AND column_name IN ('revision', 'edited_at');

SELECT indexrelid::regclass, indisvalid FROM pg_index
WHERE indexrelid = to_regclass('public.index_entries_on_edited_at_and_id');
```

Then finish its work by hand. Add whatever is missing, mark the migration as run, and run the rest:

```sql
SET statement_timeout = 0;
SET lock_timeout = '10s';
ALTER TABLE entries ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1;
ALTER TABLE entries ADD COLUMN IF NOT EXISTS edited_at timestamp(6) without time zone;

SET lock_timeout = 0;
DROP INDEX CONCURRENTLY IF EXISTS index_entries_on_edited_at_and_id;  -- only if it is invalid
CREATE INDEX CONCURRENTLY IF NOT EXISTS index_entries_on_edited_at_and_id
  ON entries (edited_at, id) WHERE edited_at IS NOT NULL;
ANALYZE entries;

INSERT INTO schema_migrations (version) VALUES ('20261030120000');
```

```bash
bin/rails db:migrate
```

`lock_timeout = 0` is safe for the index build: the build waits on old transactions without blocking anyone else. Keep 10 s on the `ALTER`s, which do block other queries while they wait.

## Step two: code

- [ ] **Bring main into `api-v3-oauth`.** The migration files and `structure.sql` are the same on both branches, so they merge cleanly. Run `bin/rails test`.
- [ ] **Deploy web and Sidekiq together.**
- [ ] **API v3 is off for everyone** until you turn it on for each user. That flag covers the settings page, OAuth authorization and the API itself. To try it yourself:

```ruby
User.find_by!(email: "you@example.com").setting_on!(:api_v3)
```

- [ ] **Mark Feedbin's own apps as first-party** after creating them, so their tokens get the `account` scope:

```bash
bin/rails "api_v3:first_party[<application uid>]"
```

- [ ] **Expect the crawler to start counting edits.** `revision` goes up and `edited_at` is set whenever an entry changes. `index_entries_on_edited_at_and_id` grows only as edits come in.

### Rollback

- [ ] **Revert the code and leave the schema.** Step one already ran today's code on it.
