# Unused Code Sweep — Design

- **Date:** 2026-10-01
- **Repo:** `~/Sites/feedbin`
- **Branch:** `cleanup` (clean at `def7bae6`)
- **Status:** Approved by Ben on 2026-10-01.

## 1. Goal

Find and delete the orphaned code in the Feedbin Rails app, in one systematic sweep. The repo gets deletions only. The sweep must not change the behavior of the app. The automated checks and a click-through in Safari prove this after each category.

## 2. Decisions

| Topic | Decision |
| --- | --- |
| Scope | Orphaned code only. Features that still run stay, even when nobody uses them. |
| Durability | One-time sweep. The repo gets deletions only, plus the record in `doc/plans/`: this spec, the plan, and the finder scripts. |
| Approach | Top-down static sweep, by category, callers before callees. `debride` and a route-to-action diff are inputs to the Ruby steps. |
| Verification | Automated checks and a Safari click-through after every category. |
| Documents | This spec, the plan, and the scripts are in `doc/plans/`. Ben asked for this after he reviewed the plan. |

## 3. Out of scope

- **Gems.** A full Gemfile audit was done on 2026-10-01.
- **Dead features.** This is code that still runs but serves a closed service or an unused feature. Examples are `Share::Readability`, Evernote and Tumblr (OAuth 1), Twitter rendering, and the legacy CoffeeScript and Sass pipeline as a whole.
- **Database tables and columns.**
- **Production runtime coverage.**
- **Refactors of the code that remains.** The only edit to remaining code is the removal of a reference to a deleted unit. An example is the entry for a deleted action in an `only:` list.
- **Maintained tooling or test guards.** The scripts in `doc/plans/unused-code-sweep/bin/` are a record of this sweep. CI does not run them, and nobody maintains them.

## 4. Definitions

- **Unit.** One method, class, module, template, asset, route, job, Rake task, test, fixture, or CSS rule.
- **Orphaned.** Nothing in this repo, in a sibling service, or in an external client can reach the unit.
- **Candidate.** A unit that a scratchpad script reports as possibly orphaned. A candidate is not confirmed.
- **Confirmed orphan.** A candidate that meets the evidence standard in section 5.3.
- **Computed name.** A name that the code builds at runtime, for example `svg_tag "icon-share-#{service}"`.
- **Kept list.** Candidates that stay, each with the reason.
- **Decision list.** Candidates that only Ben can decide on. The sweep never deletes these by itself.

## 5. Rules

### 5.1 Reachable until a check proves otherwise

A unit in one of these groups is reachable. Static evidence alone never makes it a confirmed orphan.

1. **Public routes.** These include:
   - every route in the `api` subdomain blocks (`api/v1`, `api/public/v1`, `api/podcasts/v1`, `api/v2`);
   - `extension/v1`, `app_store`, and every mounted engine;
   - every UI route that a page outside the app can link to. Examples are links in sent emails, the bookmarklet, embeds, the public settings pages, and feed URLs.
2. **Jobs.** Other services can enqueue a job by its class name. The `feed_crawler`, `image_crawler`, and `favicon_crawler` receivers are known examples. So every job class with no caller in this repo goes on the decision list, not on the delete list. Jobs in `lib/clock.rb` and classes in a `Sidekiq::Client.push` or `push_bulk` call have a caller in this repo.
3. **Computed names.** Step 0 makes an inventory of every site that builds a name at runtime. For each site, the inventory lists all the values that the site can produce. Each unit with one of those names is reachable. Sites to look for:
   - `send`, `public_send`, `method(`, `try(`, `respond_to?`
   - `constantize`, `safe_constantize`, `classify` (for example `SupportedSharingService#klass`)
   - `svg_tag`, `render`, `partial:`, and `json.partial!` with an interpolated name
   - `data-behavior`, `data-controller`, and CSS class strings with interpolation
4. **Framework entry points.** Examples:
   - callbacks and validations named by a symbol (`before_action`, `after_commit`, `validate`);
   - `perform`, mailer actions, and the Phlex `view_template`;
   - the Stimulus lifecycle methods (`connect`, `disconnect`, `*TargetConnected`, `*ValueChanged`);
   - overrides such as `to_param`, `as_json`, `to_s`, `<=>`, `method_missing`, and `respond_to_missing?`;
   - initializers and files in `config/`.
5. **CSS for content from outside.** Feed content, extracted content, newsletters, and embeds contain HTML that Feedbin did not write. A CSS rule in `.content-styles` (or a similar content scope) that targets a class from that HTML is reachable. An example is `blockquote.twitter-tweet`. A class that Feedbin's own Ruby code adds to content is checked like any other class.

### 5.2 The decision list

These go on the decision list. Ben decides each one: delete it or keep it.

1. Every job class with no caller in this repo, including one-off backfills such as `BackfillGuid` and `UpdateDefaultColumn`.
2. Every Rake task in `lib/tasks` with no caller.
3. Every file in `script/` with no caller.
4. Every public route (5.1, item 1) with no caller in this repo. The sweep only lists these. It does not delete them.

### 5.3 Evidence standard

A candidate becomes a confirmed orphan only when all three conditions are true:

1. A whole-word search for its name finds no caller outside the unit itself and its own tests. The search covers `app`, `lib`, `config`, `db/seeds.rb`, `script`, `bin`, `public`, and `test`.
2. No computed-name site from the step 0 inventory can produce the name.
3. The unit is not in a group in 5.1 or 5.2.

A unit that only its own tests call is an orphan. Its tests go out with it.

After the deletion, the automated checks (section 7.1) and the click-through (section 7.2) must pass.

When there is a doubt, the unit stays. It goes on the kept list with the reason.

## 6. Sweep order and detection

The sweep goes from callers to callees. When a step deletes a caller, the units that only it called become orphans. The next category then finds them in the same pass.

Each step writes one candidate file to the scratchpad. The file has three lists: deleted, kept (with reasons), and decision list.

### Step 0: Preparation

1. Check that `~/Sites/feedkit` has no uncommitted edits. Feedbin runs against that working copy, so uncommitted edits there can break the baseline.
2. Record the baselines:
   - the unit and integration results (`bundle exec rake`);
   - the system test results (`bin/rails test:system`);
   - the `standardrb` offense count for each file;
   - `bin/rails zeitwerk:check`;
   - an asset precompile, followed by `assets:clobber`;
   - the click-through baseline screenshots (section 7.2).
3. Make the computed-name inventory (5.1, item 3).
4. Check that `gem exec debride --rails` can parse the code. The app runs Ruby 4.0. If `debride` cannot parse the code, use a scratchpad script built on Prism (Ruby's built-in parser) instead. The script collects each `def` name and each call, symbol, and string reference, and reports the names with no reference.

### Steps 1–9

| # | Category | How the script finds candidates | Known traps |
| --- | --- | --- | --- |
| 1 | Routes and controller actions | Diff `rails routes` against the public controller methods. A candidate is an action with no route, a route with no action and no template, or a UI route whose `*_path` or `*_url` helper has no caller. | Rule 5.1 item 1 applies. JavaScript can get URLs from data attributes, so the search includes `.coffee` and `.js` files. |
| 2 | Views | ERB and jbuilder partials, and Phlex views and components, that no `render` call, `partial:` call, `json.partial!` call, or `ClassName.new` reaches. | Computed partial names. Templates for actions that step 1 deleted. |
| 3 | Mailers | Mailer methods with no caller, and their templates. | Mailer previews in `test/mailers/previews`. Methods called through a variable with `deliver_later`. |
| 4 | Helpers and presenters | `debride` on `app/helpers` and `app/presenters`. Then a search of the views for each name. | Presenter methods called through `@template`. |
| 5 | Models, jobs, `lib`, initializers | `debride` for methods and scopes. A class name with no reference. A job with no `perform_async`, `perform_in`, `Sidekiq::Client.push`, or `lib/clock.rb` entry. | Rule 5.1 item 2. Rule 5.2. Associations and callbacks look unused to `debride`. |
| 6 | Front-end code | Stimulus controllers with no `data-controller`. Stimulus methods with no `data-action`. CoffeeScript `feedbin.*` functions with no caller. `data-behavior` handlers with no view that emits that value. | The search includes Phlex `data:` hashes and Ruby strings, not only ERB. |
| 7 | Styles | Class names in `application.scss`, `theme.scss`, and `functions.scss` that appear nowhere in views, Ruby, CoffeeScript, or JavaScript. | Rule 5.1 item 5. Classes built at runtime, such as `"theme-#{x}"`. The step removes whole rules only, not shared mixins. Large: split into several commits. |
| 8 | Assets | SVG icons, images, and fonts with no reference after steps 1–7. | `svg_tag` names built from service, number, and embed-source values. |
| 9 | Final pass | Run all the scripts again. Repeat until a pass finds no new confirmed orphans. | None. |

## 7. Verification

### 7.1 Automated checks, after each category

1. `bin/rails zeitwerk:check`. This finds a deleted constant that some file still loads.
2. `bundle exec standardrb --cache false`. The offense count for each file must not go up from the baseline. The house style breaks some Standard layout rules on purpose, so the target is "no increase", not zero.
3. `source ~/.bash_profile && bundle exec rake` for the unit and integration tests.
4. `rm -rf public/assets tmp/cache/assets`, then `bin/rails test:system`.
5. For steps 6–8 only: an asset precompile, then `bin/rails assets:clobber`. This finds a missing Sass mixin or a missing asset reference.

Each run must match the baseline. A failure that is also in the baseline is noted and does not stop the sweep.

### 7.2 Click-through, after each category

**Tools:**

- **Safari MCP** (`mcp__safari-mcp__*`) does all clicks, typing, and keyboard shortcuts. It also reads the console and takes the page screenshots for the diff.
- **Computer use** takes screenshots of the real Safari window for the visual check. Computer use gives browsers a read-only tier, so it cannot click or type in Safari.
- **The diff script** in the scratchpad compares each page screenshot to its baseline with `magick compare`. On this Mac, a bare `compare` runs Araxis Merge, not ImageMagick.

**Setup, once in step 0:**

1. Run `touch tmp/restart.txt`, then load one page, so puma-dev boots the current code.
2. Sign in at `https://feedbin.resolv.app/auto_sign_in`.
3. Set a fixed viewport size, so the screenshots can be compared.
4. Walk the smoke route below. Save a page screenshot of each screen. These are the baseline screenshots.
5. Walk the smoke route a second time, with no code change. Diff the two runs. For each screen, the largest difference between the two runs is the noise threshold for that screen.

**The smoke route:**

1. **Reader.** Load the app. Select a feed. Open an entry. Use the keyboard shortcuts: `j`/`k`, star, and mark unread.
2. **Entry tools.** Open the share menu. Use extract (full content). Play a podcast and a YouTube embed, if the dev data has them.
3. **Search.** Run a search. Open a saved search.
4. **Dialogs.** Add feed. Edit feed. Tags.
5. **Settings.** Open each item in the settings navigation. This includes account, appearance, billing, subscriptions, newsletters, pages, import/export, sharing, and actions.
6. **Admin.** Open the admin pages.

Each action that changes data is reversed in the same route (for example, star and then unstar). This keeps the dev data the same between runs. If the dev data has no podcast or YouTube entry, the route skips that item, and the final report says so.

**The check after each category:**

1. Run `touch tmp/restart.txt`, because deleted classes and initializers do not reload.
2. Walk the smoke route again.
3. For each screen, read the console for errors. Read `log/development.log` for `Completed 500`.
4. Run the diff script against the baseline screenshots. Relative times and unread counts change between runs, so the script reports the size of the changed area. I read each screen whose difference is above its noise threshold (setup item 5), with a computer use screenshot of the real window.
5. Do extra checks for the screens that the category touched:
   - After step 1, open each remaining route in the controllers that lost an action.
   - After step 2, open each screen that rendered a deleted partial's neighbors.
   - After step 3, open each remaining preview at `/rails/mailers`.
   - After steps 6–8, use each feature whose JavaScript, styles, or icons changed.

## 8. Commits

- One commit per category on `cleanup`, for example "Remove unused partials". A large category, such as styles, gets several commits.
- Each commit passes all the checks in section 7 by itself. This keeps `git revert` and `git bisect` simple.
- The commits do not have a co-author line.

## 9. Failure handling

| Event | Action |
| --- | --- |
| A test fails because the unit is in use. | Restore the unit. Put it on the kept list with the reason. Do not change the test to fit the deletion. |
| A test exists only to cover the deleted unit. | Delete the test in the same commit. |
| A failure matches the baseline. | Note it. Continue. |
| The click-through finds a console error, a `Completed 500`, or a screen difference with no explanation. | Same as a failed test: restore the unit and put it on the kept list. |
| A test run produces no output for minutes. | Check Postgres with `nc -z -G 5 postgres.feedbin.orb.local 5432`. If it does not answer, OrbStack needs a restart. |

## 10. Environment notes

- Tests, the database, and `standardrb` need the sandbox off. The sandbox blocks the test server's port and the OrbStack connections.
- Test output goes to a log file in the scratchpad (absolute path). Do not pipe a test run through `tail`: the RTK hook holds the output until the run ends, so the run looks stopped.
- The unit suite takes about 20–35 seconds. The system suite takes about 27 seconds.
- `bin/rails test:system` ignores `TEST=`. Use `bin/rails test <path>` to run one file.
- The scratchpad is specific to one session. The copies in `doc/plans/` are the source. The plan's Task 1 copies the scripts into the current session's scratchpad, and they run from there, so their output stays out of the repo.

## 11. Output

At the end, the chat gets three things:

1. The lines removed, by category.
2. The kept list, with reasons.
3. The decision list.

## 12. Success criteria

1. A final pass of all the scripts finds no new confirmed orphans.
2. Every commit passes the automated checks in section 7.1.
3. The final click-through has no console errors, no `Completed 500`, and no screen difference without an explanation.
4. The kept list and the decision list are complete, and each entry has a reason.

## 13. Second pass: dead-method finder (2026-10-03)

The first pass searched method names only, so two methods with one name hid each other, and a class whose methods call each other looked used. The second pass adds a finder that knows owners and scopes.

### 13.1 Tools (in `unused-code-sweep/bin/`)

| File | Job |
| --- | --- |
| `method_index.rb` | Prism index of defs (full nested owner, instance or singleton side, line range), references (receiver kind, lexical owner and nesting), constant references, namespaces, interpolated-name patterns, and `send` with a non-literal name. Plain Ruby. |
| `method_index_test.rb` | Fixture tests for the index. `ruby doc/plans/unused-code-sweep/bin/method_index_test.rb` |
| `dead_methods.rb` | Loads the app, resolves each def at runtime, and decides which references can reach it. Run outside the sandbox (it needs the test database): `RAILS_ENV=test bin/rails runner doc/plans/unused-code-sweep/bin/dead_methods.rb`. About 3 seconds. Writes `tmp/dead_methods/`. |
| `open_sends_reviewed.tsv` | `send(var)` sites reviewed by hand, with the names each one can call. |
| `coverage_hook.rb` | Optional. Method coverage from a test run: `RUBYOPT="-r$PWD/doc/plans/unused-code-sweep/bin/coverage_hook.rb" bundle exec rake`. The finder adds a coverage column. |
| `dead_methods_expectations.rb` | Regression checks: live code that an earlier version flagged by mistake, and dead code it must find. Run after the finder. |

### 13.2 How a reference reaches a def

- Symbols, words in strings and templates, top-level code, and blocks that frameworks run with `instance_exec` reach every def with that name.
- `obj.name` with an unknown receiver reaches every non-private def with that name.
- `Const.name` resolves `Const` the way Ruby does (lexical scopes, then ancestors, then top level) and reaches only defs on its singleton side. A mailer constant also reaches its public actions.
- `name`, `self.name` and `super` reach a def only when the caller's class and the def's class can be the same object. A module's instance methods also reach class level when something extends the module.
- Anything that cannot be resolved counts as reaching.

A def is kept, not reported, when it overrides an ancestor's method, is a routed action, is an entry point, is defined dynamically or inside a template, or matches a strong dynamic-name pattern or an unreviewed `send(var)` on a receiver that can hold it.

### 13.3 Buckets

`1-shadowed`, `2-no-reference`, `3-test-only`, `4-only-from-dead` and `5-name-used-elsewhere` are strong evidence. `6-loose-pattern`, `7-unresolved` and `8-gem-word` (the name is a word in gem or stdlib source, so a library may call it as a hook) need a careful look: `8` correctly holds `JsonConverter.dump` and the `MercuryParser` Marshal hooks. `namespaces.tsv` lists classes and modules that nothing outside their own bodies names. A job there is a decision, not a deletion: it can be queued from the console or sit in the Sidekiq scheduled set.

### 13.4 Validation

On `main` the finder reported every method that the first pass deleted from a class that still exists (33 of 57 deleted defs; three of them in bucket 8). The other 24 were in classes deleted whole, and the namespace check reported 10 of those 13 classes.

### 13.5 Results

Deleted after a manual check of each candidate: three batches on 2026-10-03 (models and mailers; helpers, presenters and controllers; jobs and views). Left as decisions for Ben: `AppStoreNotificationData` (only tests use it); the jobs `BackfillGuid`, `BackfillProviderIds`, `NewsletterUpdater`, `PodcastClearUnused`, `QueuedEntryLimiter` and `SaveTwitterUsers` (nothing in the repo queues them); `OnboardingMessage` and the five `MarketingMailer#onboarding_*` emails (the code that queues them is commented out in `User`); and `lib/redis_protocol.rb` (a standalone script that the app never loads).
