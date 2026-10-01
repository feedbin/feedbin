# Unused Code Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the orphaned code in `~/Sites/feedbin`, one category at a time, with no change to the behavior of the app.

**Architecture:** Scratchpad scripts list the candidates for each category. A person checks each candidate by hand against a triage list. Confirmed orphans are deleted with their tests. After each category, an automated check script and a Safari click-through must match the baseline from Task 1, and then the category is committed. This work deletes code, so no task writes a new test. The "test" for each deletion is the baseline comparison.

**Tech Stack:** Ruby 4.0.7, Rails 8.1, Prism (Ruby's built-in parser), `git grep`, ImageMagick 7 (`magick`), Sprockets, Safari MCP (`mcp__safari-mcp__*`), computer use (`mcp__computer-use__*`).

**Spec:** `doc/plans/2026-10-01-unused-code-sweep-design.md`. The scripts are in `doc/plans/unused-code-sweep/bin/`. Read the spec before Task 1. Its section numbers (for example "spec 5.1") appear in this plan.

## Global Constraints

- Repo `~/Sites/feedbin`, branch `cleanup`. Apart from the record in `doc/plans/` (the spec, this plan, and the scripts), the repo gets deletions only. No other new file is committed.
- Out of scope: gems, dead features, database tables and columns, production coverage, refactors of remaining code (spec 3).
- Never delete a job class, a public route, a Rake task, or a `script/` file without Ben's decision (spec 5.2).
- When there is a doubt, keep the unit and put it on the kept list with the reason (spec 5.3).
- Prefix every Ruby or Rails command with `source ~/.bash_profile >/dev/null 2>&1;` (Ben's global instruction).
- Shell variables do not persist between Bash tool calls. Start each command with `SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep;`.
- Tests, the database, `standardrb`, and `pick_entries.rb` run outside the sandbox (`dangerouslyDisableSandbox: true`). The sandbox blocks the test port and the OrbStack host names.
- Do not pipe a test run through `tail` or `head`. Test output goes to log files.
- A command that runs longer than one minute must print progress. `check.sh` and `run_all.sh` print one line per step.
- Use `magick compare`, never a bare `compare` (that runs Araxis Merge on this Mac).
- Commit messages have no `Co-Authored-By` line and no AI attribution.
- Browser work uses Safari MCP (`mcp__safari-mcp__*`), not the Browser pane. Computer use has a read-only tier in Safari: it takes screenshots only.
- The scripts run from a scratchpad copy (Task 1 step 0), never from `doc/plans/`, so their output stays out of the repo. The `SWEEP=` path in the commands is the scratchpad of the session that wrote this plan. In another session, change it in every command to `<that session's scratchpad>/sweep`.

## Review Focus

These five failure modes can pass every test and still break the app. Each one has a check in the task that owns it.

1. **A caller outside the repo.** Another service enqueues a job by class name, or the iOS app, an email, or Apple calls a public route. Expected: such a unit is never deleted without Ben's decision. Check: Task 3 step 7 and Task 7 step 7 (`git diff` must not delete a job file or a public route line).
2. **A computed name that the inventory misses.** An icon or a share partial disappears, and `svg_tag` raises "Icon missing" only on a screen that the tests do not render. Expected: every computed name still resolves. Check: `verify_computed.rb` in Task 4 step 7, Task 10 step 6, and Task 11 step 3.
3. **A CSS class from third-party HTML.** A rule for feed content, highlight.js, Bigfoot footnotes, or the MediaElement player is deleted. Expected: entries with code, footnotes, and audio look the same. Check: Task 9 step 5 (no deleted line contains `content-styles` without review) and smoke screens s10–s12.
4. **Stale code under test.** puma-dev or the asset cache serves the old JavaScript, so the click-through tests code that is gone. Expected: the browser runs the current source. Check: Task 8 step 7 (the served `web.js` must not contain a deleted function name).
5. **A screen that the dev data cannot show.** The dev data has no podcast, tweet, or newsletter entry, so the click-through skips it. Expected: each skipped screen is listed, not hidden. Check: Task 2 step 2 records `NONE` rows, and Task 11 step 6 reports them.

## Files

The source of the scripts is `doc/plans/unused-code-sweep/bin/`. Task 1 step 0 copies them to `$SWEEP/bin`. They run from there, and all their output stays in the scratchpad.

| Path (under `$SWEEP`) | Purpose |
| --- | --- |
| `bin/lib.rb` | Shared helpers: `git grep` with name boundaries, the search paths, the computed-name inventory, the TSV output. |
| `bin/computed_sites.rb` | Lists every place that builds a name at runtime → `out/computed_auto.tsv`. |
| `bin/seed_computed.rb` | Builds the reviewed inventory `out/computed.tsv` from `computed_auto.tsv`. |
| `bin/routes.rb` | Step 1 finder (runner). |
| `bin/views.rb` | Step 2 finder (runner). |
| `bin/mailers.rb` | Step 3 finder (runner). |
| `bin/ruby_methods.rb` | Steps 4 and 5: methods with no caller (Prism). |
| `bin/constants.rb` | Step 5: classes, modules, and jobs with no reference. |
| `bin/config_keys.rb` | Step 5: custom config keys that nothing reads. |
| `bin/stimulus.rb` | Step 6: Stimulus controllers and methods. |
| `bin/coffee.rb` | Step 6: CoffeeScript functions and `data-behavior` selectors. |
| `bin/styles.rb` | Step 7: classes in the compiled `application.css` (runner). |
| `bin/assets.rb` | Step 8: SVG icons, images, and fonts. |
| `bin/verify_computed.rb` | Guard: every computed icon and partial name still resolves (runner). |
| `bin/run_all.sh` | Runs every finder in order (about 2 minutes). |
| `bin/check.sh` | Automated checks for one category (about 2–3 minutes). |
| `bin/pick_entries.rb` | Picks one dev entry of each kind for the smoke route (runner, needs the database). |
| `bin/shotdiff.rb` | Screenshot diff against the baseline. |
| `out/<category>.tsv` | Finder output. Columns: `status unit defined_at prod_refs test_refs note`. `status` is `candidate`, `kept`, or `decision`. Used units are not written. |
| `out/ledger.tsv` | The record of every decision. Columns: `category unit defined_at outcome reason`. `outcome` is `deleted`, `kept`, or `decision`. |
| `out/checks/<label>/` | Logs from `check.sh`. |
| `shots/<label>/` | Screenshots from one click-through. |
| `out/dryrun-2026-10-01/` | Finder output from the planning dry run. It exists only in the planning session's scratchpad. The dry-run table below has its counts. |

All scripts were written and run against the repo during planning on 2026-10-01. Each one passes `ruby -c` or `bash -n`, and the Ruby scripts pass `standardrb`. A full rerun after the style fixes gave the same counts as the table below. `check.sh` and `pick_entries.rb` were not run end to end, because the OrbStack network was down. Task 1 runs them first.

**Planning dry-run counts** (before any deletion, with the seeded inventory). Use them to see if a finder breaks:

| Finder | candidate | decision | kept |
| --- | --- | --- | --- |
| routes | 101 | 65 | 7 |
| views | 19 | 0 | 76 |
| mailers | 2 | 0 | 0 |
| helpers | 15 | 0 | 1 |
| methods | 34 | 0 | 408 |
| constants | 15 | 8 | 7 |
| config_keys | 1 | 0 | 0 |
| stimulus | 2 | 0 | 0 |
| coffee | 32 | 0 | 0 |
| styles | 78 | 0 | 155 |
| assets | 16 | 0 | 55 |

## Procedures

Each category task uses these four procedures. They are written once here, and each task names the label to use.

### Procedure A: automated checks

1. Run this with `run_in_background: true` and `dangerouslyDisableSandbox: true`. Add `--assets` for Tasks 8, 9, and 10.

   ```bash
   SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && bash $SWEEP/bin/check.sh <label> > $SWEEP/out/checks/<label>.out 2>&1
   ```

2. Read `$SWEEP/out/checks/<label>.out` to follow the progress. Each step prints one line. The full run takes about 2–3 minutes.
3. If no new line appears for 3 minutes, run `nc -z -G 5 postgres.feedbin.orb.local 5432` outside the sandbox. If it fails, stop and ask Ben to restart OrbStack. Do not restart it yourself.
4. Pass condition: the last line is `RESULT: same as baseline`.
5. On `RESULT: WORSE than baseline`: read the named log in `$SWEEP/out/checks/<label>/`. Apply Procedure F.

### Procedure C: click-through

**Setup:**

1. Run `touch ~/Sites/feedbin/tmp/restart.txt`.
2. Record where the log ends:

   ```bash
   SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; mkdir -p $SWEEP/shots/<label> && wc -l < ~/Sites/feedbin/log/development.log > $SWEEP/shots/<label>/logstart
   ```

3. Call `mcp__safari-mcp__navigate_to_url` with `https://feedbin.resolv.app/`. Then call `mcp__safari-mcp__wait_for_navigation`. The first load after a restart can take 20 seconds.
4. Call `mcp__safari-mcp__set_viewport_size` with `width: 1440, height: 900`.
5. Call `mcp__safari-mcp__browser_console_messages` with `clear: true`, to drop old messages.

**The smoke route.** For each row, do the action, wait 1 second, and call `mcp__safari-mcp__screenshot` with `savePath: "$SWEEP/shots/<label>/<id>.png"` (write the full path). After each screenshot, call `mcp__safari-mcp__browser_console_messages` with `level_filter: ["error"]` and write down each error.

"Open the `<kind>` row" means: read `$SWEEP/out/smoke_entries.tsv`, click the feed title of that row in the feed list (`page_interactions`, `type: "click"`, `text: <feed_title>`), and then click the entry title (`text: <entry_title>`). If the row is `NONE`, skip the screen and write it down.

To click something with no visible text, first call `mcp__safari-mcp__get_page_content` to get its node UID, then click the node. If it has no UID, click it with `mcp__safari-mcp__evaluate_javascript` and the selector given.

| ID | Screen | Action |
| --- | --- | --- |
| s01-home | Reader | Navigate to `https://feedbin.resolv.app/`. Wait 3 seconds. |
| s02-feed | Feed | Click the feed title of the `default` row. |
| s03-entry | Entry | Click the entry title of the `default` row. |
| s04-star | Starred | `keyPress` `s`. Screenshot. Then `keyPress` `s` again to unstar. |
| s05-unread | Unread | `keyPress` `m`. Screenshot. Then `keyPress` `m` again. |
| s06-nav | Next and previous | `keyPress` `j`, then `keyPress` `k`. |
| s07-share | Share menu | `keyPress` `f`. Screenshot. Then `keyPress` `Escape`. |
| s08-extract | Full content | `keyPress` `c`. Wait 3 seconds. Screenshot. Then `keyPress` `c` again. |
| s09-shortcuts | Shortcuts dialog | `keyPress` `?`. Screenshot. Then `keyPress` `Escape`. |
| s10-code | Code block | Open the `code` row. |
| s11-footnote | Footnote | Open the `footnotes` row. Click the first `.bigfoot-footnote__button`. Screenshot. Then `keyPress` `Escape`. |
| s12-podcast | Podcast | Open the `podcast` row. Screenshot. Click the play control (`get_page_content`, label "Play"). Wait 2 seconds. Screenshot as `s12b-podcast-playing`. Click pause. |
| s13-youtube | YouTube | Open the `youtube` row. Screenshot. Click the element with `data-controller~="embed-player"`. Wait 2 seconds. Screenshot as `s13b-youtube-playing`. |
| s14-tweet | Tweet | Open the `tweet` row. |
| s15-micropost | Micropost | Open the `micropost` row. |
| s16-newsletter | Newsletter | Open the `newsletter` row. |
| s17-search | Search | `keyPress` `/`. `type` `the` with `pressReturn: true`. Wait 2 seconds. |
| s18-saved-search | Saved search | Click the first saved search in the feed list. If there is none, skip and write it down. |
| s19-add-feed | Add feed dialog | `keyPress` `a`. Screenshot. Then `keyPress` `Escape`. |
| s20-edit-feed | Edit feed dialog | Click the feed title of the `default` row. Click its menu button (selector `[data-behavior~=feeds_target] .selected [data-behavior~=toggle_source_menu]`). Click `text: "Edit"`. Screenshot. Then `keyPress` `Escape`. |
| s21-tag-menu | Tag menu | Click the menu button of the first tag row in the feed list. Screenshot. Then `keyPress` `Escape`. |
| s30-settings | Settings | Navigate to `https://feedbin.resolv.app/settings`. |
| s31-appearance | Appearance | Navigate to `/settings/appearance`. |
| s32-account | Account | Navigate to `/settings/account`. |
| s33-billing | Billing | Navigate to `/settings/billing`. Wait 3 seconds (Stripe loads). |
| s34-subscriptions | Subscriptions | Navigate to `/settings/subscriptions`. |
| s35-subscription-edit | One subscription | Click the first subscription in the list. |
| s36-newsletters | Newsletters | Navigate to `/settings/newsletters`. |
| s37-actions | Actions | Navigate to `/settings/actions`. |
| s38-mutes | Mutes | Navigate to `/mutes`. |
| s39-sharing | Share and save | Navigate to `/settings/sharing`. |
| s40-import-export | Import and export | Navigate to `/settings/import_export`. |
| s50-admin-users | Admin customers | Navigate to `/admin/users`. |
| s51-admin-feeds | Admin feeds | Navigate to `/admin/feeds`. |

The route reverses each change it makes (star, unread, extract), so the dev data stays the same between runs.

**After the route:**

6. Look for server errors that the route caused:

   ```bash
   SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && tail -n +$(( $(cat $SWEEP/shots/<label>/logstart) + 1 )) log/development.log | grep -nE "Completed 5[0-9][0-9]|ActionView::Template::Error|NoMethodError|NameError|Icon missing" || echo "no server errors"
   ```

7. Compare the screenshots:

   ```bash
   SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/shotdiff.rb compare $SWEEP/shots/baseline $SWEEP/shots/<label>
   ```

8. For each `FLAG` line: read `$SWEEP/shots/<label>/diff/<id>.png` and `$SWEEP/shots/<label>/<id>.png` with the Read tool. Open that screen again in Safari. Call `mcp__computer-use__app_screenshot` with `app: "com.apple.Safari"` to see the real window. Decide: the difference is dynamic content (a time or a count), or it is a regression.
9. Pass condition: no console error that the baseline did not have, step 6 prints `no server errors`, and each `FLAG` has an explanation.
10. On a failure, apply Procedure F.

### Procedure F: a deletion broke something

1. Find the unit that caused the failure. Use the stack trace, the failing test, or the screen.
2. Restore that unit with `git checkout -- <files>` (or restore the deleted lines by hand).
3. Add a ledger row with `outcome` `kept` and the reason, for example `kept<TAB>used by X: test Y failed`.
4. Do not change a test so that it fits a deletion.
5. Run the procedure that failed again.

### Procedure L: ledger rows

Add one row to `$SWEEP/out/ledger.tsv` for each candidate and each decision-list row in the category. Use tabs between columns:

```bash
SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; printf '%s\t%s\t%s\t%s\t%s\n' "<category>" "<unit>" "<defined_at>" "<deleted|kept|decision>" "<reason>" >> $SWEEP/out/ledger.tsv
```

---

### Task 1: Baselines and the computed-name inventory (spec step 0, part 1)

**Files:**
- Create (scratchpad): `$SWEEP/out/base_sha.txt`, `$SWEEP/out/computed.tsv`, `$SWEEP/out/baseline/*.tsv`, `$SWEEP/out/checks/baseline/`, `$SWEEP/out/verify_computed.baseline.txt`, `$SWEEP/out/ledger.tsv`
- Repo: no change

**Interfaces:**
- Consumes: the scripts in `doc/plans/unused-code-sweep/bin/`.
- Produces: `$SWEEP/bin/` (the copy every later task runs), `out/computed.tsv` (read by every finder through `lib.rb#computed`), `out/checks/baseline/` (read by `check.sh`), `out/verify_computed.baseline.txt`, `out/base_sha.txt`.

- [ ] **Step 0: Copy the scripts to the scratchpad.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; mkdir -p $SWEEP/bin $SWEEP/out && cp ~/Sites/feedbin/doc/plans/unused-code-sweep/bin/* $SWEEP/bin/ && ls $SWEEP/bin | wc -l
  ```

  Expected: `18`.

- [ ] **Step 1: Check the working copies.**

  ```bash
  cd ~/Sites/feedbin && git status --short && git rev-parse --abbrev-ref HEAD && git -C ~/Sites/feedkit status --short
  ```

  Expected: no output from either `git status`, and the branch is `cleanup`. If `~/Sites/feedkit` has edits, stop and ask Ben. Feedbin runs against that working copy.

- [ ] **Step 2: Check that the database is reachable.** Run outside the sandbox: `nc -z -G 5 postgres.feedbin.orb.local 5432`. Expected: exit status 0. If it fails, ask Ben to restart OrbStack, and wait.

- [ ] **Step 3: Record the base commit and make the folders.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && git rev-parse HEAD > $SWEEP/out/base_sha.txt && mkdir -p $SWEEP/out/checks $SWEEP/out/baseline $SWEEP/shots && printf 'category\tunit\tdefined_at\toutcome\treason\n' > $SWEEP/out/ledger.tsv && cat $SWEEP/out/base_sha.txt
  ```

- [ ] **Step 4: Build the inventory.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/computed_sites.rb && ruby $SWEEP/bin/seed_computed.rb
  ```

  Expected: `80 prefixes` (or close) and `41 rows`. If the counts are far off, read `DROP` and `NARROW` in `seed_computed.rb`.

- [ ] **Step 5: Review the inventory by hand.** Read `$SWEEP/out/computed.tsv`. For each row, open the site in the third column and confirm two things:
  1. The prefix or name can name a unit (an icon, a partial, a class, a CSS class).
  2. The prefix is not much broader than the values the site can produce.

  If a prefix is too broad, add it to `NARROW` in `seed_computed.rb` with its exact values, as `icon-` is. If a prefix cannot name a unit, add it to `DROP`. Then run Step 4 again.

- [ ] **Step 6: Optional cross-check with `debride`.** The approved approach lists `debride` as an input. This step downloads the `debride` gem from rubygems.org into a temporary gem home. It does not change the Gemfile.

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; GEM_HOME=$TMPDIR/debride-gems gem exec debride --rails app lib > $SWEEP/out/debride.txt 2>&1; tail -5 $SWEEP/out/debride.txt
  ```

  If `debride` cannot parse the Ruby 4.0 code, write that in the ledger notes and continue. `ruby_methods.rb` is the primary method finder. If it runs, Tasks 6 and 7 read `out/debride.txt` as a second list.

- [ ] **Step 7: Run all finders and keep the baseline counts.** This takes about 2 minutes and prints one line per finder.

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && bash $SWEEP/bin/run_all.sh 2>&1 | grep -v "not writable\|home directory"; cp $SWEEP/out/*.tsv $SWEEP/out/baseline/
  ```

  Expected: counts close to the dry-run table. The "prefixes not yet reviewed" list must be empty.

- [ ] **Step 8: Write the computed-name baseline.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/verify_computed.rb
  ```

  Expected: `baseline written (2 already missing)`: `icon-share-readability.svg` and `icon-share-app_dot_net.svg`. Both are dead features, so they are out of scope.

- [ ] **Step 9: Run the automated baseline.** Use Procedure A with label `baseline` and `--assets`. Expected: both suites finish. Read `$SWEEP/out/checks/baseline/failures.txt`. Every failure in it is a baseline failure. Tell Ben about each one before Task 3.

- [ ] **Step 10: No commit.** This task changes no repo file.

### Task 2: Click-through baseline (spec step 0, part 2)

**Files:**
- Create (scratchpad): `$SWEEP/out/smoke_entries.tsv`, `$SWEEP/shots/baseline/`, `$SWEEP/shots/baseline2/`, `$SWEEP/shots/thresholds.tsv`
- Repo: no change

**Interfaces:**
- Consumes: Procedure C.
- Produces: `shots/baseline/` and `shots/thresholds.tsv` (read by `shotdiff.rb compare` in every later task), `out/smoke_entries.tsv`.

- [ ] **Step 1: Get computer use access to Safari.** Call `mcp__computer-use__request_access` with `apps: ["Safari"]` and the reason "Take screenshots of the Feedbin dev site to check that code deletions change nothing." Expected: Safari is granted at the read tier.

- [ ] **Step 2: Pick the smoke entries.** Run outside the sandbox:

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/pick_entries.rb 2>&1 | grep -v "not writable\|home directory"
  ```

  Expected: one line per kind. Write down each `NONE` kind. The click-through cannot show those screens.

- [ ] **Step 3: Sign in.** Call `mcp__safari-mcp__navigate_to_url` with `https://feedbin.resolv.app/auto_sign_in`. Then navigate to `https://feedbin.resolv.app/settings/account` and confirm that the email matches the `user:` line from Step 2. Do not type a password anywhere.

- [ ] **Step 4: Walk the route for the baseline.** Use Procedure C with label `baseline`. Skip steps 7 and 8 of "After the route" (there is nothing to compare yet). Step 6 must print `no server errors`. If it does not, tell Ben: the app has an error before any deletion.

- [ ] **Step 5: Walk the route a second time.** Use Procedure C with label `baseline2`, with no code change. Skip steps 7 and 8.

- [ ] **Step 6: Calibrate the noise thresholds.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/shotdiff.rb calibrate $SWEEP/shots/baseline $SWEEP/shots/baseline2
  ```

  Expected: one line per screen, with a small pixel count. A `MISSING` or `SIZE` line means the two walks were not the same. Walk `baseline2` again before you continue.

- [ ] **Step 7: Check the comparison.** Run step 7 of "After the route" with label `baseline2`. Expected: every line starts with `ok`.

- [ ] **Step 8: No commit.**

### Task 3: Routes and controller actions (spec step 1)

**Files:**
- Modify: `config/routes.rb`, files in `app/controllers/`
- Delete: action templates in `app/views/` for deleted actions, and tests in `test/controllers/` that cover only deleted actions

**Interfaces:**
- Consumes: `out/computed.tsv`, the baselines from Tasks 1 and 2.
- Produces: commit "Remove unused routes and controller actions".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/routes.rb 2>&1 | grep -v "not writable\|home directory"; column -t -s$'\t' $SWEEP/out/routes.tsv | less -S
  ```

- [ ] **Step 2: Triage each `candidate` row.** The `note` column tells which kind of row it is.
  1. **"route with no action and no template".** The route can only fail, so it is a confirmed orphan. Remove it: add or narrow the `only:` (or `except:`) list on its `resources` line, or delete its explicit route line. Example: `resources :users` with no `index`, `show`, or `edit` action becomes `resources :users, only: [...]` with the actions that exist.
  2. **"public method with no route".** The finder found no caller by name. Check that no `before_action`, `helper_method`, `rescue_from`, or `send` uses it. Then it is a confirmed orphan.
  3. **A `_path` row.** Check these in order:
     - If the note says "is a model", search for polymorphic use: `git grep -nE "(form_with|form_for|link_to|button_to|redirect_to|url_for|polymorphic_(path|url))[ (].*\b<singular>\b" -- app`. A hit means it is used.
     - Ask: can a caller outside the repo reach it? Examples: the iOS app (paths under `/app/`, and the `TurbolinksFeedbin` user agent), a link in a sent email, the bookmarklet, Apple (`/.well-known`), or a webhook (POST from Stripe, the App Store, Postmark, or WebSub). If yes, the outcome is `decision`.
     - Otherwise it is a confirmed orphan.
- [ ] **Step 3: Copy each `decision` row** to the ledger with Procedure L (`outcome` `decision`). Do not change them.
- [ ] **Step 4: Delete the confirmed orphans.** For each deleted action, also delete its templates (`app/views/<controller>/<action>.*`) and every test that covers only that action. If a test file covers other actions too, delete only the test methods for the deleted action.
- [ ] **Step 5: Record the ledger rows** with Procedure L, category `routes`.
- [ ] **Step 6: Run Procedure A** with label `03-routes`. Run Procedure C with label `03-routes`. As extra checks, navigate to each remaining GET route in the controllers that lost an action.
- [ ] **Step 7: Check Review Focus item 1.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && git diff -U0 $(cat $SWEEP/out/base_sha.txt) -- config/routes.rb | grep -E '^-' | grep -vE '^---' | grep -nE 'api|v1|v2|extension|app_store|well-known|webhook|stripe|notifications' || echo "no public route lines removed"
  ```

  Expected: `no public route lines removed`. Each line it prints needs Ben's decision before the commit.
- [ ] **Step 8: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A config/routes.rb app/controllers app/views test && git commit -m "Remove unused routes and controller actions"
  ```

### Task 4: Views, partials, and Phlex components (spec step 2)

**Files:**
- Delete: files in `app/views/` (ERB, jbuilder, builder, and Phlex `.rb`), and tests in `test/components/`, `test/views/`
- Modify: only to remove a reference to a deleted view

**Interfaces:**
- Consumes: Task 3 commit.
- Produces: commit "Remove unused views and components".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/views.rb 2>&1 | grep -v "not writable\|home directory"; column -t -s$'\t' $SWEEP/out/views.tsv
  ```

- [ ] **Step 2: Triage each `candidate` row.**
  1. **Partial.** Look for an implicit render (`render @records`, `render record`, `collection:`). Look for `j render` in `.js.erb` files. Look for a relative `render "name"` from a controller whose views live in another folder.
  2. **Phlex class.** Search for the class name as a string. Look for a `layout` declaration (for example a lambda that returns `ApplicationLayout`). Look for a `Phlex::Kit` call `Name(...)`.
  3. **Action template.** Look for `render :name`, `render "folder/name"`, or `template:` in its controller. Templates in `errors/` are used by `config.exceptions_app = routes`. Keep them. For `shared/errors/500.js.erb`, look for a `rescue_from` that renders it.
  4. If no caller is found, it is a confirmed orphan.
- [ ] **Step 3: Delete the confirmed orphans** and the tests that cover only them.
- [ ] **Step 4: Record the ledger rows** with Procedure L, category `views`.
- [ ] **Step 5: Run Procedure A** with label `04-views`.
- [ ] **Step 6: Run Procedure C** with label `04-views`. As extra checks, open each screen that rendered a neighbor of a deleted partial (a partial in the same folder).
- [ ] **Step 7: Check Review Focus item 2.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/verify_computed.rb 2>&1 | grep -v "not writable\|home directory"
  ```

  Expected: `verify_computed: ok (2 missing at baseline, none new)`.
- [ ] **Step 8: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app/views test && git commit -m "Remove unused views and components"
  ```

### Task 5: Mailers (spec step 3)

**Files:**
- Modify: `app/mailers/*.rb`, `test/mailers/previews/*.rb`
- Delete: mailer templates in `app/views/<mailer>/`, mailer tests for deleted methods

**Interfaces:**
- Consumes: Task 4 commit.
- Produces: commit "Remove unused mailer methods".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/mailers.rb 2>&1 | grep -v "not writable\|home directory"; column -t -s$'\t' $SWEEP/out/mailers.tsv
  ```

  The dry run found `MarketingMailer#member_discount` (only a preview calls it) and `UserMailer#mailtest` (no template).
- [ ] **Step 2: Triage each `candidate` row.** A mailer method that an operator calls from a console, such as a delivery test, is like a one-off job. Its outcome is `decision`. A method that only a preview or a test calls, and that no job, model, or controller calls, is a confirmed orphan. Its preview method and its tests go with it.
- [ ] **Step 3: Delete the confirmed orphans** with their templates, preview methods, and tests.
- [ ] **Step 4: Record the ledger rows** with Procedure L, category `mailers`.
- [ ] **Step 5: Run Procedure A** with label `05-mailers`.
- [ ] **Step 6: Run Procedure C** with label `05-mailers`. As extra checks, navigate to `https://feedbin.resolv.app/rails/mailers` and open each remaining preview. Each must render with no error.
- [ ] **Step 7: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app/mailers app/views test && git commit -m "Remove unused mailer methods"
  ```

### Task 6: Helpers and presenters (spec step 4)

**Files:**
- Modify: `app/helpers/*.rb`, `app/presenters/*.rb`
- Delete: helper and presenter tests for deleted methods

**Interfaces:**
- Consumes: Task 5 commit.
- Produces: commit "Remove unused helper and presenter methods".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/ruby_methods.rb helpers app/helpers app/presenters && column -t -s$'\t' $SWEEP/out/helpers.tsv
  ```

  If `out/debride.txt` exists, also read the names it reports for `app/helpers` and `app/presenters`. Treat each one that is not in `helpers.tsv` as a candidate too.
- [ ] **Step 2: Triage each `candidate` row.**
  1. Look for a `register_value_helper :name` or a `register_output_helper :name` in `app/views/components/application_component.rb`.
  2. Look for `helper_method :name` in a controller.
  3. Look for `send`, `public_send`, or `try` with a variable near the callers of the presenter.
  4. A `component` helper caller uses symbols (`component :name`). The finder counts those.
  5. If none of these, it is a confirmed orphan.
- [ ] **Step 3: Delete the confirmed orphans** and the tests that cover only them.
- [ ] **Step 4: Record the ledger rows** with Procedure L, category `helpers`.
- [ ] **Step 5: Run Procedure A** with label `06-helpers`.
- [ ] **Step 6: Run Procedure C** with label `06-helpers`. As extra checks, open the screens that render entries (s03, s10–s16), because `EntryPresenter` lost methods in the dry run.
- [ ] **Step 7: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app/helpers app/presenters test && git commit -m "Remove unused helper and presenter methods"
  ```

### Task 7: Models, jobs, `lib`, initializers, and other Ruby methods (spec step 5)

**Files:**
- Modify: `app/models/`, `app/jobs/`, `lib/`, `config/initializers/`, `app/controllers/` (private methods), `app/mailers/`, `app/uploaders/`, `app/views/**/*.rb` (Phlex methods)
- Delete: classes and modules that are confirmed orphans, and their tests and fixtures

**Interfaces:**
- Consumes: Task 6 commit.
- Produces: commit "Remove unused models, classes, and methods". If the diff is large, make one commit per directory, each with its own Procedure A and C.

- [ ] **Step 1: Run the finders.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/ruby_methods.rb methods app/models app/jobs lib config/initializers app/controllers app/mailers app/uploaders app/views && ruby $SWEEP/bin/constants.rb && ruby $SWEEP/bin/config_keys.rb && for f in methods constants config_keys; do column -t -s$'\t' $SWEEP/out/$f.tsv; done
  ```

- [ ] **Step 2: Triage the method candidates.**
  1. **A framework or gem hook.** The method overrides a method of a parent class from a gem, for example an ActiveRecord type's `cast`, a CarrierWave `store_dir`, or a Rails `append_info_to_payload`. Look for `super` in its body, or look up the parent class. It is kept. Also add its name to `ENTRY` in `ruby_methods.rb`.
  2. **A name built at runtime.** Look for a `send` site that builds names from data. For example, `OnboardingMessage#perform` calls `send(@message)`, and its `onboarding_*` names come from job arguments. Keep these with the reason.
  3. **Called only from a test.** It is a confirmed orphan. Delete its tests too.
- [ ] **Step 3: Triage the constant candidates.**
  1. **A job class (`decision` rows).** Copy each row to the ledger with `outcome` `decision`. Do not delete it.
  2. **A reopened library constant** (for example `Enumerable` in `config/initializers/sort.rb`). It is kept as a constant. Its methods are already in `methods.tsv`.
  3. **Middleware in `lib/`** (for example `ConditionalCompression`, `NoCompression`). Look in `config/application.rb`, `config/environments/*.rb`, and `config.ru` for the constant or its name as a string.
  4. **A class that only tests use** (test_refs > 0, prod_refs 0). It is a confirmed orphan. Delete its tests and fixtures too.
- [ ] **Step 4: Triage the config key candidates.** Look for a read through another receiver, for example `Rails.configuration.<key>` or `config.<key>` in a view. If there is none, delete the assignment.
- [ ] **Step 4b: Put the Rake tasks and `script/` files on the decision list** (spec 5.2 items 2 and 3). An operator starts these by name, so the code has no caller by design. List them with any caller that exists:

  ```bash
  cd ~/Sites/feedbin && for f in $(git ls-files lib/tasks script); do echo "== $f"; for t in $(grep -oE "task[ (]+:?\"?[a-z_]+" "$f" | grep -oE "[a-z_]+$"); do echo "  task $t: $(git grep -n -w "$t" -- . ":(exclude)$f" | head -3 | tr '\n' ' ')"; done; done
  ```

  Add one ledger row per file with `outcome` `decision` and the callers it printed (or "no caller"). The dry run found four Rake files (`feedbin_deploy_diff`, `feedbin_generate_coupon`, `feedbin_make_admin`, `feedbin_reset`) and `script/rails`.
- [ ] **Step 5: Delete the confirmed orphans.** Delete a file only when every unit in it is a confirmed orphan. Otherwise delete only the orphan methods.
- [ ] **Step 6: Record the ledger rows** with Procedure L, categories `methods`, `constants`, and `config_keys`.
- [ ] **Step 7: Check Review Focus item 1.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && git diff --name-status $(cat $SWEEP/out/base_sha.txt) -- app/jobs lib/tasks script | grep -E '^D' || echo "no job, Rake task, or script file deleted"
  ```

  Expected: `no job, Rake task, or script file deleted`. A deleted file under `app/jobs/*/lib/` is allowed only when `constants.tsv` listed it as a `candidate`, not as a `decision`.
- [ ] **Step 8: Run Procedure A** with label `07-ruby`.
- [ ] **Step 9: Run Procedure C** with label `07-ruby`.
- [ ] **Step 10: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app lib config test && git commit -m "Remove unused models, classes, and methods"
  ```

### Task 8: Front-end code: Stimulus and CoffeeScript (spec step 6)

**Files:**
- Modify: `app/assets/javascripts/web/*.coffee`, `app/javascript/controllers/*.js`
- Delete: Stimulus controller files that are confirmed orphans

**Interfaces:**
- Consumes: Task 7 commit.
- Produces: commit "Remove unused JavaScript".

- [ ] **Step 1: Ask Ben one question before any triage.** "Does the iOS or Mac app call `feedbin.*` JavaScript functions in the web view?" If yes, every CoffeeScript function candidate goes to the decision list, and only the `data-behavior` rows and the Stimulus rows are triaged here.
- [ ] **Step 2: Run the finders.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/stimulus.rb && ruby $SWEEP/bin/coffee.rb && column -t -s$'\t' $SWEEP/out/stimulus.tsv && column -t -s$'\t' $SWEEP/out/coffee.tsv
  ```

- [ ] **Step 3: Triage each `candidate` row.**
  1. **Stimulus controller.** Look for a `data-controller` value or a Phlex `stimulus(controller: ...)` call that a variable sets. Look for a JavaScript caller (`getControllerForElementAndIdentifier`).
  2. **Stimulus method.** Look for the method in an `actions:` hash in Phlex (snake_case) and in a `data-action` string.
  3. **CoffeeScript function.** Look for a caller in a `.js.erb` response (`feedbin.name`), and for a call through a variable (`feedbin[name]`).
  4. **`data-behavior` selector.** Look for the value in a Ruby string that is built at runtime. If no view emits it, delete the handler block in `feedbin.init` that binds the selector. Keep the rest of `init`.
- [ ] **Step 4: Delete the confirmed orphans.**
- [ ] **Step 5: Record the ledger rows** with Procedure L, categories `stimulus` and `coffee`.
- [ ] **Step 6: Run Procedure A** with label `08-javascript` and `--assets`.
- [ ] **Step 7: Check Review Focus item 4.** Run Procedure C setup steps 1–3. Then call `mcp__safari-mcp__evaluate_javascript` with this body. Replace `NAMES` with three of the deleted function names:

  ```javascript
  const names = ["NAMES"];
  const found = [];
  for (const src of [...document.scripts].map(s => s.src).filter(Boolean)) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", src, false);
    xhr.send(null);
    for (const n of names) {
      if (xhr.responseText.includes(n + ":") || xhr.responseText.includes("feedbin." + n)) found.push(n + " in " + src);
    }
  }
  return { scripts: document.scripts.length, stillServed: found };
  ```

  The tool does not accept top-level `await`, so the body uses a synchronous request. Expected: `stillServed` is an empty list. If it is not empty, run `rm -rf ~/Sites/feedbin/public/assets ~/Sites/feedbin/tmp/cache/assets`, touch `tmp/restart.txt`, and run this step again.
- [ ] **Step 8: Run Procedure C** with label `08-javascript`. As extra checks, use each feature whose script changed. Also press each shortcut key in the shortcuts dialog list once.
- [ ] **Step 9: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app/assets/javascripts app/javascript && git commit -m "Remove unused JavaScript"
  ```

### Task 9: Styles (spec step 7)

**Files:**
- Modify: `app/assets/stylesheets/application.scss`, `app/assets/stylesheets/theme.scss`, `app/assets/stylesheets/functions.scss`

**Interfaces:**
- Consumes: Task 8 commit.
- Produces: one or more commits "Remove unused CSS rules (part N)".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; bin/rails runner $SWEEP/bin/styles.rb 2>&1 | grep -v "not writable\|home directory"; awk -F'\t' '$1=="candidate"' $SWEEP/out/styles.tsv | column -t -s$'\t' | less -S
  ```

- [ ] **Step 2: Triage each `candidate` row.**
  1. Look for JavaScript that adds the class with a string that the inventory does not cover (`addClass`, `toggleClass`, `classList.add`, `className =`).
  2. Look for the class in HTML that a gem renders (for example `will_paginate` links, or Rails form errors).
  3. Look for the class in an email template or in the bookmarklet.
  4. If none of these, it is a confirmed orphan.
- [ ] **Step 3: Delete the confirmed orphans.** Delete a whole rule only when every selector in it is an orphan. When a selector list mixes orphans and used selectors, delete only the orphan selectors. Do not delete a Sass mixin, a variable, or a `@extend` target. Work in batches of about 25 classes. Each batch gets Steps 4–7 and its own commit.
- [ ] **Step 4: Record the ledger rows** for the batch with Procedure L, category `styles`.
- [ ] **Step 5: Check Review Focus item 3.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && git diff -U0 -- app/assets/stylesheets | grep -E '^-' | grep -vE '^---' | grep -nE 'content-styles|entry-content|hljs|bigfoot|mejs|footnote' || echo "no content-scope rules removed"
  ```

  Expected: `no content-scope rules removed`. Each line it prints needs a check that third-party HTML cannot carry the class (spec 5.1 item 5). If you are not sure, restore the line.
- [ ] **Step 6: Run Procedure A** with label `09-styles-<N>` and `--assets`.
- [ ] **Step 7: Run Procedure C** with label `09-styles-<N>`. The screenshot diff is the main check for this task. Read every `FLAG` with care.
- [ ] **Step 8: Commit the batch.**

  ```bash
  cd ~/Sites/feedbin && git add app/assets/stylesheets && git commit -m "Remove unused CSS rules (part <N>)"
  ```

### Task 10: Assets (spec step 8)

**Files:**
- Delete: files in `app/assets/svg/`, `app/assets/images/`, `app/assets/fonts/`

**Interfaces:**
- Consumes: Task 9 commits.
- Produces: commit "Remove unused icons and images".

- [ ] **Step 1: Run the finder.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && source ~/.bash_profile >/dev/null 2>&1; ruby $SWEEP/bin/assets.rb && column -t -s$'\t' $SWEEP/out/assets.tsv
  ```

- [ ] **Step 2: Triage each `candidate` row.**
  1. Look for the file name with its extension in CSS (`image-url`, `font-url`, `url(`), in `public/*.html`, in the web app manifest, and in the service worker view.
  2. For fonts, look for an `@font-face` that builds the file name from a variable.
  3. Look for an asset path that the native apps can request. A digest URL cannot be called from outside, but a file in `public/` can.
  4. If none of these, it is a confirmed orphan.
- [ ] **Step 3: Delete the confirmed orphans.**
- [ ] **Step 4: Record the ledger rows** with Procedure L, category `assets`.
- [ ] **Step 5: Run Procedure A** with label `10-assets` and `--assets`.
- [ ] **Step 6: Check Review Focus item 2.** Run the `verify_computed.rb` command from Task 4 step 7. Expected: `none new`.
- [ ] **Step 7: Run Procedure C** with label `10-assets`.
- [ ] **Step 8: Commit.**

  ```bash
  cd ~/Sites/feedbin && git add -A app/assets && git commit -m "Remove unused icons and images"
  ```

### Task 11: Final pass and report (spec step 9)

**Files:**
- Repo: changes only when the pass finds new confirmed orphans
- Create (scratchpad): `$SWEEP/out/final/*.tsv`, `$SWEEP/out/report.md`

**Interfaces:**
- Consumes: all earlier commits, `out/ledger.tsv`, `out/baseline/*.tsv`.
- Produces: the report for Ben (spec 11).

- [ ] **Step 1: Run all finders again.**

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; cd ~/Sites/feedbin && bash $SWEEP/bin/run_all.sh 2>&1 | grep -v "not writable\|home directory"; mkdir -p $SWEEP/out/final && cp $SWEEP/out/*.tsv $SWEEP/out/final/
  ```

- [ ] **Step 2: Find the new candidates.** A new candidate is a `candidate` row that is not in the ledger.

  ```bash
  SWEEP=/private/tmp/claude-501/-Users-ben-Sites-feedbin/c01c4b71-471d-4360-8e15-b9cddfd10b60/scratchpad/sweep; for f in $SWEEP/out/final/*.tsv; do awk -F'\t' 'NR==FNR {seen[$2]=1; next} $1=="candidate" && !seen[$2] {print FILENAME": "$2"\t"$3}' $SWEEP/out/ledger.tsv "$f"; done
  ```

  If it prints rows, go back to the task for that category and triage only those rows. Then run this task again from Step 1. Stop when it prints nothing.
- [ ] **Step 3: Run `verify_computed.rb`** (the command from Task 4 step 7). Expected: `none new`.
- [ ] **Step 4: Run Procedure A** with label `11-final` and `--assets`.
- [ ] **Step 5: Run Procedure C** with label `11-final`. Every `FLAG` must have an explanation.
- [ ] **Step 6: Write the report** to `$SWEEP/out/report.md`. It has these parts:
  1. Lines removed, by category: `git diff --shortstat $(cat $SWEEP/out/base_sha.txt) -- <paths>` for each category's paths, and the commit list from `git log --oneline $(cat $SWEEP/out/base_sha.txt)..HEAD`.
  2. The kept list: every ledger row with `outcome` `kept`, with its reason.
  3. The decision list: every ledger row with `outcome` `decision`.
  4. The skipped smoke screens: each `NONE` kind from Task 2 step 2.
  5. Found but out of scope: `icon-share-readability.svg` and `icon-share-app_dot_net.svg` are missing for two registered services (Readability and App.net). Both services are closed. This is a dead feature for a later decision.
- [ ] **Step 7: Show the report to Ben** in chat. Ask Ben to decide each row on the decision list. Do not push the branch and do not open a pull request unless Ben asks.
