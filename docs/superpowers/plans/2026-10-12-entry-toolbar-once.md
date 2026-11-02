# Entry Toolbar Once Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the entry toolbar one time per page and drive it with a Stimulus controller, so that the preload sends small toolbar data for each entry in place of toolbar HTML.

**Architecture:** The server sends a `toolbar` data object (with a favicon HTML fragment) for each entry. A Phlex component renders one toolbar in `logged_in.html.erb`. A Stimulus controller fills it when an entry opens and sends the star, read, extract, sticky, and delete requests with `fetch`. Old tabs keep working, because the server answers the old JavaScript too (step 1 of the spec).

**Tech Stack:** Rails 8.1, Phlex 2.4, Stimulus (importmap), CoffeeScript/jQuery (Sprockets), Minitest, Capybara with Cuprite.

**Spec:** `docs/superpowers/specs/2026-10-12-entry-toolbar-once-design.md`

## Global Constraints

- The toolbar must look the same. Keep the markup classes of `entries/_show.html.erb`: `.toolbar-wrap`, `.entry-toolbar`, `.site-info`, `.feed-button`, `.entry-feed-title`, `.entry-buttons`, `.entry-button-wrap`, `.entry-button`, `.button-toggle-content`, `.button-toggle-starred`, `.button-toggle-read`.
- All new JavaScript is Stimulus. Controller identifier: `entry-toolbar`. Component: `App::EntryToolbarComponent`.
- URL template placeholders: `ENTRY_ID` and `FEED_ID`.
- Preload version parameter: `v=2`.
- Window events: `entry-toolbar:show` (detail: toolbar data or `null`), `entry-toolbar:star`, `entry-toolbar:read`, `entry-toolbar:extract` (detail: `{automatic: true}` for the automatic extract).
- Delete confirm text: `Are you sure you want to delete this page?`
- Step 1 only. Keep `content`, the JS templates (`extracts/entry.js.erb`, `entries/destroy.js.erb`, `settings/sticky.js.erb`, `entries/show.js.erb`), and the old toolbar partials, because old tabs use them.
- No new error handling. Star and read stay optimistic.
- Never interpolate into SQL.
- There is no JavaScript test runner. System tests and source wiring tests verify the JavaScript.
- Run commands with `source ~/.bash_profile &&` first. Run tests outside the sandbox. Run system tests with `bin/rails test <path>`, never `rails test:system TEST=`. Do not pipe test output through `tail` or `head`.
- Before a system test run after a JavaScript edit, run `rm -rf tmp/cache/assets` (stale assets).
- Commit messages have no `Co-Authored-By` line.

## Review Focus

1. The user opens entry B while a star request for entry A runs. The star stays on A, and B does not change. Test: Task 3, "a star request keeps its entry when another entry opens".
2. A shortcut (`s`, `m`, `c`) when no entry is open, for example after a delete. Nothing happens and no request goes out. Test: Task 3, "delete a pages entry" presses `s` after the delete.
3. A feed with a custom title. The header shows the custom title when the entry opens, not only after a rename. Test: Task 3, "the header shows the custom feed title".
4. A Pages entry whose URL has no host. `header_title` is `""`, not `null`, so the header shows no `null` text. Test: Task 1, "toolbar data for a pages entry with no host".
5. A tweet entry, which has no feed title in the entry list. The header still shows the feed title. Test: Task 3, the current "Show tweet" test gets a header assertion.

---

### Task 1: Toolbar data in the entry responses

**Files:**
- Modify: `app/presenters/entry_presenter.rb` (add `toolbar_data`)
- Modify: `app/controllers/entries_controller.rb` (`show`, `preload`, `entries_by_id`)
- Modify: `app/controllers/application_controller.rb:82` (`preload_entries_path`)
- Test: `test/controllers/entries_controller_test.rb`
- Test: `test/views/query_count_test.rb`

**Interfaces:**
- Produces: `EntryPresenter#toolbar_data(subscriptions) -> Hash` with symbol keys `id` (Integer), `feed_id` (Integer), `url` (String), `title` (String or nil), `feed_title` (String), `twitter_id` (String), `header_title` (String, never nil), `pages` (Boolean), `subscribed` (Boolean), `favicon` (String, `FaviconComponent` HTML).
- Produces: `EntriesController#entries_by_id(entry_ids, toolbar_html:) -> Hash{Integer => Hash}`. Each value is `{toolbar:, inner_content:, feed_id:}`, plus `content:` (old toolbar HTML) when `toolbar_html` is true.
- Produces: `feedbin.data.preload_entries_path == "/entries/preload.json?v=2"`.

- [ ] **Step 1: Write the failing controller tests**

In `entries_controller_test.rb`, add:

```ruby
TOOLBAR_KEYS = %w[favicon feed_id feed_title header_title id pages subscribed title twitter_id url]

test "preload with v=2 sends toolbar data and no toolbar html" do
  login_as @user
  get :preload, params: {ids: @entries.map(&:id).join(","), v: "2"}, format: :json
  data = JSON.parse(@response.body)
  @entries.each do |entry|
    toolbar = data[entry.id.to_s]["toolbar"]
    assert_equal TOOLBAR_KEYS, toolbar.keys.sort
    refute data[entry.id.to_s].key?("content")
    assert_equal entry.id, toolbar["id"]
    assert_equal entry.feed.title, toolbar["header_title"]
    assert_equal false, toolbar["pages"]
    assert_equal true, toolbar["subscribed"]
    assert_includes toolbar["favicon"], "favicon-wrap"
  end
  refute_includes @response.body, "toggle_settings_menu"
end

test "preload without v keeps the toolbar html for old tabs" do
  # data[id]["content"] includes "toggle_starred", and data[id]["toolbar"] exists
end

test "toolbar data for a pages entry" do
  # Pages feed (feed_type: :pages), subscribed, entry url "https://example.com/article"
  # toolbar: pages == true, subscribed == false, header_title == "example.com"
end

test "toolbar data for a pages entry with no host" do
  # entry url "/x" -> header_title == ""
end

test "toolbar data for a starred entry from a feed with no subscription" do
  # new Feed + entry, StarredEntry.create_from_owners(@user, entry), no subscription
  # preload v=2 -> toolbar["subscribed"] == false
end

test "show as js sends toolbar html and toolbar data" do
  # get :show, xhr: true -> assigns(:entries)[id] has :content and :toolbar
end

test "show as html sends toolbar data only" do
  # get :show (html) -> assigns(:entries)[id] has :toolbar, no :content
  # assigns(:data)[:preload_entries_path] == "/entries/preload.json?v=2"
end
```

Make the pages feed as the current destroy test does: `Feed.create!(feed_url: "https://pages.example/x", host: "pages.example", title: "P", feed_type: :pages)` and `@user.subscriptions.create!(feed: feed)`.

In `query_count_test.rb`, add a class `PreloadQueryCountTest < ActionController::TestCase` with `tests EntriesController` and `include QueryCounting`, in the style of `SidebarQueryCountTest`:

```ruby
test "preload does not query favicons once per pages entry" do
  # Pages feed with 1 entry on host one.example vs 5 entries on 5 hosts
  # capture_sql { get :preload, params: {ids:, v: "2"}, format: :json }
  # matching(statements, /FROM "images"/i).count is the same for both sizes
end
```

- [ ] **Step 2: Run the tests and make sure they fail**

Run: `source ~/.bash_profile && bin/rails test test/controllers/entries_controller_test.rb test/views/query_count_test.rb`
Expected: the new tests fail (no `toolbar` key, `content` present with `v=2`, query count grows). The old tests pass.

- [ ] **Step 3: Implement `EntryPresenter#toolbar_data(subscriptions)`**

Use `favicon(entry.feed, entry).to_s` (it reads `@locals[:favicons]`). `header_title` is `entry.hostname.to_s` for Pages, else `@template.strip_tags(entry.feed.title).to_s`. `subscribed` is `!entry.feed.pages? && subscriptions.include?(entry.feed_id)`. `twitter_id` is `entry.twitter_id || ""`.

- [ ] **Step 4: Implement `entries_by_id(entry_ids, toolbar_html:)`**

Preload `:owned_image_records, :channel_image_record`. Compute `favicons = Image.favicons_for_entries(entries)` and `template = view_context` one time. For each entry, build `EntryPresenter.new(entry, {favicons: favicons}, template)` and call `toolbar_data`. Render `entries/show` into `content` only when `toolbar_html` is true. `preload` passes `toolbar_html: params[:v] != "2"`. `show` passes `toolbar_html: !request.format.html?`. In `application_controller.rb`, change the path to `preload_entries_path(format: :json, v: 2)`.

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `source ~/.bash_profile && bin/rails test test/controllers/entries_controller_test.rb test/views/query_count_test.rb`
Expected: all pass, including "preload renders a settings button, not the settings menu" (the old-tab path).

- [ ] **Step 6: Commit**

```bash
git add app/presenters/entry_presenter.rb app/controllers/entries_controller.rb app/controllers/application_controller.rb test/controllers/entries_controller_test.rb test/views/query_count_test.rb
git commit -m "Send toolbar data with each preloaded entry"
```

### Task 2: HTML and JSON responses for extract, delete, and sticky

**Files:**
- Modify: `app/controllers/extracts_controller.rb` (`entry`)
- Modify: `app/controllers/entries_controller.rb` (`destroy`)
- Modify: `app/controllers/settings_controller.rb` (`sticky`)
- Test: `test/controllers/extracts_controller_test.rb`, `test/controllers/entries_controller_test.rb`, `test/controllers/settings_controller_test.rb`

**Interfaces:**
- Produces: `GET /extracts/:id/entry?extract=true` with `Accept: text/html` returns the `extracts/_entry` partial, no layout.
- Produces: `DELETE /entries/:id` with `Accept: application/json` returns `204`.
- Produces: `POST /settings/sticky/:feed_id` with `Accept: application/json` returns `{"view_inline": Boolean}`, or `204` when the user has no subscription to the feed.
- A request with a JS `Accept` header, or with `*/*`, gets the current JS template.

- [ ] **Step 1: Write the failing tests**

```ruby
# extracts_controller_test.rb
test "entry renders the extract partial as html" do
  # MercuryParser.stub :parse, OpenStruct.new(content: content)
  # @request.accept = "text/html"; get :entry, params: {id:, extract: "true"}, xhr: true
  assert_response :success
  assert_equal "text/html", @response.media_type
  assert_includes @response.body, content
  refute_includes @response.body, "feedbin.extractCache"
end

test "entry keeps the js response for old tabs" do
  # get :entry, params: {id:, extract: "true"}, xhr: true
  assert_includes @response.body, "feedbin.extractCache"
end

# entries_controller_test.rb
test "destroy answers json with no content" do
  # Pages entry as in the current destroy test; @request.accept = "application/json"
  # delete :destroy, params: {id:}, xhr: true
  assert_response :no_content
  # EntryDeleter#delete_entries got [[feed.id, entry.id]]
end

# settings_controller_test.rb
test "sticky answers json with the new view_inline" do
  # @request.accept = "application/json"; post :sticky, params: {feed_id:}, xhr: true
  assert_equal({"view_inline" => !initial}, JSON.parse(@response.body))
end

test "sticky answers no content when the user has no subscription" do
  # @request.accept = "application/json", no subscription
  assert_response :no_content
end
```

Add `assert_includes @response.body, "readability_settings"` to the current test "sticky toggles view_inline on the matching subscription".

- [ ] **Step 2: Run the tests and make sure they fail**

Run: `source ~/.bash_profile && bin/rails test test/controllers/extracts_controller_test.rb test/controllers/entries_controller_test.rb test/controllers/settings_controller_test.rb`
Expected: the new tests fail with `ActionController::UnknownFormat` or a wrong status.

- [ ] **Step 3: Add `respond_to` to the three actions**

- `entry`: `format.js` first, then `format.html` renders `partial: "extracts/entry"` with locals `content:`, `content_info:`, `entry:`, `user:`.
- `destroy`: `format.js` first, then `format.json { head :no_content }`.
- `sticky`: change `head :ok` for a missing subscription to `head :no_content`. Then `format.js` first, then `format.json { render json: {view_inline: @subscription.view_inline} }`. JS must be first, because Rails picks the first format for `Accept: */*`.

- [ ] **Step 4: Run the tests and make sure they pass**

Same command as step 2. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/extracts_controller.rb app/controllers/entries_controller.rb app/controllers/settings_controller.rb test/controllers
git commit -m "Answer extract, delete, and sticky requests without JavaScript"
```

### Task 3: One toolbar with show, star, read, delete, and header

**Files:**
- Create: `app/views/components/app/entry_toolbar_component.rb`
- Create: `app/javascript/controllers/entry_toolbar_controller.js`
- Create: `app/javascript/helpers/request_helpers.js`
- Modify: `app/javascript/helpers/index.js`
- Modify: `app/views/site/logged_in.html.erb:79`
- Modify: `app/assets/javascripts/web/_site.js.coffee` (`updateEntryContent`, `showEntry`, `preloadEntries`, `formatEntryContent`, remove `applyStarred`, store the `CountsBehavior` object)
- Modify: `app/assets/javascripts/web/counts_behavior.js.coffee` (`showEntryContent`, `toggleRead`, `toggleStarred`, `mark`, `unmark`, constructor)
- Modify: `app/assets/javascripts/web/keyboard.js.coffee` (`s`, `m`)
- Modify: `app/assets/stylesheets/application.scss:2724-2755`
- Modify: `test/application_system_test_case.rb` (`finished_all_ajax_requests?`)
- Test: `test/components/entry_toolbar_component_test.rb`, `test/views/toolbar_wiring_test.rb`, `test/system/article_test.rb`

**Interfaces:**
- Consumes: the toolbar data from Task 1, and the delete `204` from Task 2.
- Produces: `App::EntryToolbarComponent.new` (no arguments) with `STIMULUS_CONTROLLER = :entry_toolbar`, `ENTRY_ID = "ENTRY_ID"`, `FEED_ID = "FEED_ID"`.
- Produces: controller values `entryId` and `feedId` (Number); `starred`, `read`, `extract`, `loading`, `pages`, `subscribed` (Boolean); `starredUrl`, `unreadUrl`, `extractUrl`, `deleteUrl`, `stickyUrl`, `editSubscriptionUrl` (String). Targets: `header` (two, the link and the plain variant), `feedLink`, `sourceLink`. Actions: `show`, `toggleStarred`, `toggleRead`, `toggleExtract`, `delete`.
- Produces: `request(url, {method = "GET", accept = "application/json", signal} = {}) -> Promise<Response>` in `helpers/request_helpers.js`. It sends `Accept`, `X-CSRF-Token` (from `meta[name="csrf-token"]`), and `X-Requested-With: XMLHttpRequest`. It throws when `response.ok` is false. It keeps `window.feedbin.activeRequests` as the count of open requests.
- Produces: `feedbin.countsBehavior.toggleStarred(entryId, feedId) -> Boolean` (the new starred state) and `feedbin.countsBehavior.toggleRead(entryId, feedId) -> Boolean` (the new read state).
- Produces: `feedbin.updateEntryContent(content = "")`. An empty `content` clears the entry and dispatches `entry-toolbar:show` with `null`.

- [ ] **Step 1: Take a "before" screenshot**

In Safari, sign in at `https://feedbin.resolv.app/auto_sign_in`, open an entry, and save a screenshot of the entry toolbar to the scratchpad. Task 5 compares against it.

- [ ] **Step 2: Write the failing component and wiring tests**

`test/components/entry_toolbar_component_test.rb` (`ComponentTestCase`, parse with `Nokogiri::HTML5.fragment`):

```ruby
test "renders the controller root with url templates" do
  root = toolbar.at_css("[data-controller~='entry-toolbar']")
  assert_equal "/entries/ENTRY_ID/starred_entries", root["data-entry-toolbar-starred-url-value"]
  assert_equal "/entries/ENTRY_ID/unread_entries", root["data-entry-toolbar-unread-url-value"]
  assert_equal "/extracts/ENTRY_ID/entry", root["data-entry-toolbar-extract-url-value"]
  assert_equal "/entries/ENTRY_ID", root["data-entry-toolbar-delete-url-value"]
  assert_equal "/settings/sticky/FEED_ID", root["data-entry-toolbar-sticky-url-value"]
  assert_equal "/subscriptions/FEED_ID/edit?app=true", root["data-entry-toolbar-edit-subscription-url-value"]
  assert_equal "0", root["data-entry-toolbar-entry-id-value"]
  %w[starred read extract loading pages subscribed].each do |name|
    assert_equal "false", root["data-entry-toolbar-#{name}-value"]
  end
end

test "has no forms" do
  assert_empty toolbar.css("form")
end

test "keeps the copy-link field" do
  assert toolbar.at_css("textarea#source_link_field")
end

test "every rendered value is declared by the controller" do
  # rendered: data-entry-toolbar-(.+)-value attribute names, camelized
  # declared: the keys of `static values = {...}` in entry_toolbar_controller.js
  # assert_empty rendered - declared
end
```

In `toolbar_wiring_test.rb`, run the test "only reads values it declares" for both `toolbar_controller.js` and `entry_toolbar_controller.js`. Add the same check for targets: every `this.(\w+)Target(s)?` must be in `static targets`.

- [ ] **Step 3: Write the failing system tests**

In `article_test.rb`, change "star" and "mark unread" to click `.entry-toolbar .button-toggle-starred` and `.entry-toolbar .button-toggle-read`. The state assertion becomes `[data-entry-toolbar-starred-value='true']`. Add:

```ruby
test "star with the s key"            # send_keys("s"), StarredEntry.count +1
test "mark unread with the m key"     # send_keys("m"), UnreadEntry.count +1

test "switching entries moves the toolbar to the new entry" do
  # create_feeds(@user, 2); open the entry of feed A, then the entry of feed B
  # assert_selector ".entry-toolbar", count: 1
  # within(".entry-toolbar") { assert_selector ".entry-feed-title", text: feed_b.title }
  # star -> StarredEntry for the B entry only
  # the delete button is not visible (feed is not Pages)
end

test "a star request keeps its entry when another entry opens" do
  # open A, click star, click_link B at once, wait_for_ajax
  # StarredEntry exists for A, not for B
end

test "the share menu closes when another entry opens" do
  # open A, click [data-behavior~=toggle_share_menu], open B
  # assert_no_selector ".entry-toolbar .dropdown-wrap.open"
end

test "delete a pages entry" do
  # Pages feed with subscription and create_entry; open it
  # accept_confirm("Are you sure you want to delete this page?") { click the delete button }
  # list item [data-entry-id=ID] is gone, .entry-column has no .has-content
  # then send_keys("s"): StarredEntry.count does not change
end

test "the header links to edit subscription for a subscribed feed" do
  # a.feed-button[href='/subscriptions/FEED/edit?app=true'] is visible; click opens the dialog
end

test "the header is not a link for a feed with no subscription" do
  # StarredEntry for an entry of a feed with no subscription; visit entry_path(entry)
  # no visible a.feed-button; a visible span.feed-button holds the feed title
end

test "a full page load shows the toolbar for the entry"   # visit entry_path; title + star work
test "the header shows the custom feed title"             # subscription title "My Title" before open

test "a rename changes the header after another entry opened" do
  # open A (feed 1), open B (feed 2)
  # execute_script: feedbin.data.user_titles[feed2.id] = "Renamed"; feedbin.applyUserTitles(false)
  # header shows "Renamed"
end

test "an entry with no toolbar data turns the toolbar off" do
  # open an entry; execute_script: delete feedbin.entries[ID].toolbar; feedbin.showEntry(ID)
  # assert_selector "[data-entry-toolbar-entry-id-value='0']"
  # send_keys("s"): StarredEntry.count does not change; the entry content still shows
end
```

Add `assert_selector ".entry-toolbar .entry-feed-title", text: @feed.title` to "Show tweet".

In `application_system_test_case.rb`, `finished_all_ajax_requests?` checks `jQuery.active + (window.feedbin.activeRequests || 0)`.

- [ ] **Step 4: Run the tests and make sure they fail**

Run: `source ~/.bash_profile && bin/rails test test/components/entry_toolbar_component_test.rb test/views/toolbar_wiring_test.rb`
Expected: fail, `App::EntryToolbarComponent` and the controller file do not exist.

Run: `source ~/.bash_profile && rm -rf tmp/cache/assets && bin/rails test test/system/article_test.rb`
Expected: the new and changed tests fail.

- [ ] **Step 5: Implement `App::EntryToolbarComponent`**

Copy the structure of `entries/_show.html.erb`. Differences:
- The root `.toolbar-wrap` also has class `group` and the `stimulus(...)` data. The values start at `0` and `"false"`. The URL templates use `ENTRY_ID` and `FEED_ID` in the route helpers. The actions map the four `@window` events to `show`, `toggleStarred`, `toggleRead`, and `toggleExtract`.
- Two header variants in `.site-info`, each a `header` target:
  - `a.feed-button.link` with `data-remote="true"`, `data-open-dialog` set to `Dialog::EditSubscription.dom_id`, the title `Edit Subscription`, a tooltip, the `feedLink` target, and `group-data-[entry-toolbar-subscribed-value=false]:tw-hidden`.
  - `span.feed-button` with `group-data-[entry-toolbar-subscribed-value=true]:tw-hidden`.
- The delete, extract, star, and read buttons are `button type="button"` elements in `div.entry-button-wrap`, with the same classes, icons, and titles as today. The delete wrap has `group-data-[entry-toolbar-pages-value=false]:tw-hidden`.
- Render the share, entry settings, and app settings parts with `render partial(...)`, as `Dialog::ActionResults` does.
- `textarea#source_link_field.visually-hidden` with the `sourceLink` target.

In `logged_in.html.erb`, render the component inside `[data-behavior~=entry_meta_target]`.

- [ ] **Step 6: Implement `request(...)` in `helpers/request_helpers.js`**

Export it from `helpers/index.js`.

- [ ] **Step 7: Implement `entry_toolbar_controller.js`: `show`, `toggleStarred`, `toggleRead`, `delete`**

- `show(event)`: if `event.detail` is null, set `entryIdValue = 0` and stop. Else do the eight steps of "Open an entry" in the spec. `starred` comes from `feedbin.Counts.get().isStarred(id)`. `read` is true. `extract` and `loading` are false. Fill each `header` target: `innerHTML = data.favicon`, then append a **new** `span.entry-feed-title`. For a feed that is not Pages, the span has `data-behavior="user_title"` and `data-feed-id`, and its text is `userTitle(feedId, data.header_title)`. A new span each time avoids the jQuery `.data()` cache. Set `feedLinkTarget.href` from the template. Remove `open` from each `.dropdown-wrap.open` in the toolbar.
- `toggleStarred` and `toggleRead`: stop when `entryIdValue` is 0. Read the id and feed id one time, call the `countsBehavior` toggle, set the value from its result, then `request(url, {method: "POST"}).catch(() => {})`.
- `delete`: stop when `entryIdValue` is 0 or `pagesValue` is false. Ask the confirm. Send the `DELETE` with the id at the start. On success, remove the list item and the counts, and call `feedbin.applyCounts(true)`. Call `feedbin.clearEntry()` and `feedbin.fullScreen(false)` only if `entryIdValue` is still that id.
- Leave `toggleExtract()` as an empty method. Task 4 fills it.

- [ ] **Step 8: Connect the CoffeeScript**

- `_site.js.coffee`: `feedbin.countsBehavior = new feedbin.CountsBehavior()`.
- `updateEntryContent(content = "")`: no `metaTarget`. When `content` is `""`, dispatch `entry-toolbar:show` with `null`.
- `showEntry`: call `updateEntryContent(entry.inner_content)`, then dispatch `entry-toolbar:show` with `entry.toolbar || null`, then call `formatEntryContent`.
- `preloadEntries`: count a cached entry only if it has `toolbar`.
- `formatEntryContent`: remove the `applyStarred` call. Delete `applyStarred`.
- `counts_behavior.js.coffee`: remove the two `ajax:beforeSend` hooks for `toggle_read` and `toggle_starred`. `toggleRead` and `toggleStarred` take `(entryId, feedId)` and return the new state. `mark` and `unmark` take `(property, entryId = feedbin.selectedEntry.id)`. In `showEntryContent`, use the cache only if `feedbin.entries[entry.id]?.toolbar` exists.
- `keyboard.js.coffee`: `s` and `m` dispatch `entry-toolbar:star` and `entry-toolbar:read`.
- `application.scss`: `.read &` becomes `[data-entry-toolbar-read-value="true"] &`. `.starred &` becomes `[data-entry-toolbar-starred-value="true"] &`.

- [ ] **Step 9: Run the tests and make sure they pass**

Run the two commands of step 4.
Expected: all pass, except "extract" in `article_test.rb`, which Task 4 fixes.

- [ ] **Step 10: Commit**

```bash
git add app/views/components/app/entry_toolbar_component.rb app/javascript app/views/site/logged_in.html.erb app/assets test
git commit -m "Render the entry toolbar one time and drive it with Stimulus"
```

### Task 4: Extract

**Files:**
- Modify: `app/javascript/controllers/entry_toolbar_controller.js` (`toggleExtract`)
- Modify: `app/assets/javascripts/web/_site.js.coffee` (`readability`, `readabilityActive`, remove the `updateReadability` setup and `feedbin.automaticSubmit`)
- Modify: `app/assets/javascripts/web/keyboard.js.coffee` (`c`)
- Modify: `app/assets/stylesheets/application.scss` (the `.loading` and `.active` selectors of `.button-toggle-content`)
- Test: `test/system/article_test.rb`

**Interfaces:**
- Consumes: `request(...)` and the values from Task 3, the HTML extract and the JSON sticky from Task 2.
- Produces: `feedbin.readabilityActive() -> Boolean`, read from the `data-entry-toolbar-extract-value` attribute with `.attr()`, not `.data()`.

- [ ] **Step 1: Write the failing system tests**

```ruby
test "extract" do
  # current test: click .button-toggle-content -> ".original-meta strong", text: "Originally from:"
  # click again -> the entry content shows, [data-entry-toolbar-extract-value='false']
  # assert_requested(extract_stub, times: 1)
end

test "extract with the c key"

test "a press while extract loads aborts it" do
  # stub the extract host with a 1 second delay (to_return block that sleeps)
  # send_keys("c") two times -> [data-entry-toolbar-loading-value='false'], extract false
  # after 1.5 s: assert_no_selector ".original-meta"
end

test "automatic extract for a sticky feed does not change the setting" do
  # @user.update(sticky_view_inline: "1"); subscription.update(view_inline: true)
  # open the entry -> ".original-meta" shows; subscription.reload.view_inline is still true
end
```

- [ ] **Step 2: Run the tests and make sure they fail**

Run: `source ~/.bash_profile && rm -rf tmp/cache/assets && bin/rails test test/system/article_test.rb`
Expected: the four extract tests fail.

- [ ] **Step 3: Implement `toggleExtract(event)`**

Follow "Extract" in the spec, steps 1 to 5 in that order. Stop when `entryIdValue` is 0. `automatic` is `event.detail?.automatic === true`. Sticky: `POST` with `Accept: application/json`. On `204`, change nothing. Else set `feedbin.data.readability_settings[feedId]` from `view_inline`. Extract `GET`: the URL template plus `?extract=true`, with `accept: "text/html"` and an `AbortController` signal. Store the `AbortController` in `feedbin.readabilityXHR`. Set `feedbin.readabilityXHR = null` before `formatEntryContent` runs in the success handler. A response or failure for an id that is no longer `entryIdValue` changes nothing. An `AbortError` changes nothing.

- [ ] **Step 4: Connect the CoffeeScript and the CSS**

- `readability()`: keep `changeContentView('extract')`, then dispatch `entry-toolbar:extract` with `{automatic: true}`.
- `readabilityActive()`: read the attribute.
- Remove `updateReadability` from the setup functions, and remove `feedbin.automaticSubmit`.
- `c` dispatches `entry-toolbar:extract`.
- `&.loading` becomes `[data-entry-toolbar-loading-value="true"] &`. `.button-toggle-content.active` becomes `[data-entry-toolbar-extract-value="true"] .button-toggle-content`.

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `source ~/.bash_profile && rm -rf tmp/cache/assets && bin/rails test test/system/article_test.rb`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/entry_toolbar_controller.js app/assets test/system/article_test.rb
git commit -m "Drive the extract button from the toolbar controller"
```

### Task 5: Verification and review

**Files:**
- No new files. Fixes go into the files of the earlier tasks.

- [ ] **Step 1: Run the full suite**

Run: `source ~/.bash_profile && bundle exec rake`
Run: `source ~/.bash_profile && rm -rf tmp/cache/assets && bin/rails test test/system`
Expected: 0 failures, 0 errors in both.

- [ ] **Step 2: Lint the changed Ruby files**

Run: `source ~/.bash_profile && bundle exec standardrb --cache false <changed .rb files>`
Expected: no new offense types compared with the `main` versions of the same files (aligned hashes are house style).

- [ ] **Step 3: Measure the preload again**

Run the probe of the spec with `entries_by_id(ids, toolbar_html: false)` against `toolbar_html: true` on the dev database.
Expected: the toolbar part of a 100-entry batch is about 5 ms or less, and the raw JSON is about half the size.

- [ ] **Step 4: Check the real app in Safari**

At `https://feedbin.resolv.app`:
1. Open an entry and compare the toolbar with the "before" screenshot.
2. Star, read, extract, and share.
3. Open the format menu.
4. Open a Pages entry and delete it.
5. Do steps 1 to 3 again at a narrow window width.

Expected: the toolbar looks the same as before, and every button works.

- [ ] **Step 5: Whole-branch review**

Use superpowers:requesting-code-review with a fresh reviewer on the most capable model, against `main`. Fix the confirmed findings, run steps 1 and 2 again, and commit.
