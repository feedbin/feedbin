# Deploy checklist: API v3

Two deploys, each of its own branch. **Step one** is branch `api-v3-migrations`: the seven migrations and `structure.sql`, nothing else. It runs under today's code. **Step two** is branch `api-v3-oauth`: the code, once every migration has finished.

**Step one is done.** It was deployed on 2026-11-14. `script/api_v3_prebuild.sh` took 24 minutes on db1 (`entries` 227 GB and 142M rows: 16 minutes for the `edited_at` index, 1 for `unreads`, 6 for `feed_id, created_at, id`), and the deploy's migration step then took 5 seconds.

Today's code works on the new schema. The new tables are unused, the new `entries` columns have a default or allow null, and every `unreads` query by `user_id` can use a composite index. The step-one branch passes main's test suite on the new schema.

## Step one: schema

**Build the slow parts before deploying, with `script/api_v3_prebuild.sh`.** `cap deploy` runs `db:migrate` on app4 before it publishes the release, and it pauses every Sidekiq process (`deploy:quiet`) from the start of the deploy until the restart at the end. Three of these migrations build an index over all of `entries` or `unreads`, which together take an hour or more. Left to the deploy, that is an hour or more with no background jobs, on a build that dies with your SSH session and is cancelled by the one-hour statement timeout. Built by hand first, the deploy's migrations find everything in place and finish in seconds.

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

`script/api_v3_prebuild.sh` does all of it: the two columns, the three indexes, and an `ANALYZE` of both tables. It is one file with no dependencies but `bash` and `psql`, and it runs on the database server itself.

- [x] **Start when nothing long is running:** no backfill, export, or `renderings:rebuild` pass. Before it finishes, a concurrent build waits for every transaction that started before it. The script lists the transactions open for more than 10 seconds when it starts.
- [x] **Copy the script to the database server and run it in `tmux`,** as a user that owns the tables. It refuses to start outside `tmux` or `screen`.

```bash
sudo -u postgres ./api_v3_prebuild.sh <database>
```

`MAINTENANCE_WORK_MEM=2GB` gives the index sorts more memory than the server's default. `sudo` drops the environment, so a variable goes after it, not in front:

```bash
sudo -u postgres MAINTENANCE_WORK_MEM=2GB ./api_v3_prebuild.sh <database>
```

What it does, in order:

| Step | How |
| --- | --- |
| Adds `entries.revision` and `entries.edited_at` | Each `ALTER` needs a brief exclusive lock on `entries` and rewrites no rows (Postgres 11+). It waits 10 seconds for the lock, then fails rather than stall the site, and tries again, up to ten times. |
| Builds the three indexes | `CREATE INDEX CONCURRENTLY`, one at a time, with no statement or lock timeout. Reads and writes carry on. |
| Analyzes `entries` and `unreads` | |
| Checks that no index is invalid | It exits non-zero if one is. |

- [x] **If it stops, run it again.** Every step skips what is already there, and an index an interrupted build left invalid is dropped and built again.
- [x] **Watch a build from a second console.** Postgres 11 has no progress view for index builds (`pg_stat_progress_create_index` arrived in 12), so watch the statement and the index's size. The `(edited_at, id)` index stays near empty; the other two grow in the second half of the build.

```sql
SELECT pid, now() - query_start AS running, wait_event_type, wait_event, left(query, 70)
FROM pg_stat_activity WHERE query ILIKE 'create index concurrently%';

SELECT pg_size_pretty(pg_relation_size('index_entries_on_feed_id_and_created_at_and_id'));
```

- [ ] **It ends with "Done."** and the time each build took.

### Deploy

- [ ] **Deploy branch `api-v3-migrations`.** The migrations run inside the deploy, with the usual 10 s lock timeout and one-hour statement timeout. With the columns and indexes already there, what is left is new tables, one concurrent index drop, and an `ANALYZE` after each index migration.
- [ ] **If the deploy's migration step fails,** nothing is half-built: run the deploy again. Every migration is safe to run again. The two that create tables and the one that creates the profiles table run in a transaction, and the three index migrations skip what exists and rebuild an index a failed build left invalid.

### After

- [ ] **Confirm everything ran.** `bin/rails db:migrate:status` shows all seven migrations as `up`.
- [ ] **Confirm no index is invalid.** This must return no rows:

```sql
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```
- [ ] **Watch `unreads` query times** for the next day. `index_unreads_on_user_id` is gone, and the composite indexes that start with `user_id` cover its queries.

### If you skip the build by hand

The migrations still do everything themselves. Expect the deploy to block and Sidekiq to stay paused until they finish, keep the SSH session alive, and raise `StrongMigrations.statement_timeout` in `config/initializers/strong_migrations.rb` above the longest build first: at one hour, a build that runs over is cancelled and leaves an invalid index. The `DB_STATEMENT_TIMEOUT=60min` the deploy sets does not help, because the initializer's value is applied when a migration starts.

## Step two: code

`main` is already merged into `api-v3-oauth`. Its `db/migrate` and `structure.sql` are the same as step one's, so nothing is left to migrate.

### Deploy

- [ ] **Deploy branch `api-v3-oauth`.** The deploy restarts web and Sidekiq together, which is what this needs. It installs one new gem, `doorkeeper`. It needs no new environment variable: OAuth application logos go to `UNIFIED_BUCKET_IMAGES`, which production already cannot boot without.
- [ ] **The migration step runs and finds nothing to do.** `db/seeds.rb` differs from the release before it, which is enough for the deploy to call `db:migrate`.
- [ ] **Expect a rise in render load.** This release changes how stored renderings are laid out and bumps `ContentFormatter::VERSION` to 4, so every stored rendering is rendered and written again on its first read, as after the entry renderings deploy.
- [ ] **Expect the crawler to start counting edits.** `revision` goes up and `edited_at` is set whenever an entry changes. `index_entries_on_edited_at_and_id` grows only as edits come in.

Nothing changes for anyone yet. API v3 is off for every account until it is turned on, account by account.

### Turn API v3 on, account by account

The flag is the `api_v3` setting on a user. There is no screen for it; set it in a console (`bin/rails console` in `/usr/local/srv/apps/feedbin/current` on app4):

```ruby
%w[you@example.com tester@example.com].each { User.find_by!(email: it).setting_on!(:api_v3) }
```

Who needs it:

- [ ] **You,** to see Settings > Developers and register applications.
- [ ] **Everyone who will sign in with an app that uses v3.** Without it the authorize page answers a correct password with "This account can’t connect apps yet" (or a 404 if they are already signed in on the web), and the API answers `403 restricted`. That is each tester of the new iOS app, and you.

Nobody else needs it. An application's owner needs it to manage the application, not for other people to sign in with it. To turn it off again: `user.setting_off!(:api_v3)`.

Not gated by the flag: Settings > Account lists Authorized Apps for anyone who has one, so access can always be revoked.

### Register Feedbin's own apps

One application for each app Feedbin ships. Today that is the new iOS app (`feedbin-ios-next`); the Android app does not use v3 yet.

- [ ] **Create it.** Signed in as the account that should own it, with `api_v3` on: Settings > Developers (the small link under API, `/settings/api`) > New Application.

| Field | Value |
| --- | --- |
| Name | What the authorize page shows: "*Name* is requesting access to your account". For the iOS app, `Feedbin`. |
| Redirect URIs | `feedbin-next://oauth/callback`, which is what the iOS app sends. |
| Logo | Shown above the name on the authorize page. |
| Description, URL, Contact Email | Optional; shown only on the application's own page. |

- [ ] **Copy its Client ID** from the application's page. It is generated, not chosen.
- [ ] **Mark it first-party, before anyone signs in with it.** On app4, in `/usr/local/srv/apps/feedbin/current`:

```bash
bin/rails "api_v3:first_party[<client id>]"
```

Without this its tokens are `read write` only, and the app cannot read or change the account (`/v3/account`), register a device, record a purchase or list tokens. The task also upgrades the application's existing tokens, the ones created in settings included. It prints the application's name, its scopes and how many tokens it upgraded.

- [ ] **Give the Client ID to the app.** In `feedbin-ios-next`, `Configuration/Identity.xcconfig`:

```
FEEDBIN_OAUTH_CLIENT_ID[config=Release] = <client id>
```

Release builds talk to `https://api.feedbin.com/v3/` and send people to `https://feedbin.com/oauth/authorize` to sign in.

- [ ] **Try it.** Sign in from a Release build with an account that has `api_v3` on. Then Settings > Account on the web lists the app under Authorized Apps.

### After

- [ ] **Update the API docs.** In `feedbin-api-docs`, `authentication.md` still says `GET /account` and `PATCH /account` need only `read write`, that settings are covered by `read write`, and describes the old `WWW-Authenticate` challenge. All of `/v3/account` needs `account` now, and the challenge is Doorkeeper's.

### Rollback

- [ ] **Deploy the release before it and leave the schema.** Step one already ran that code on this schema. Renderings written by this release are rendered again on first read by the old code. Applications, tokens and logos stay in the database and the image store, unused, for the next attempt.
