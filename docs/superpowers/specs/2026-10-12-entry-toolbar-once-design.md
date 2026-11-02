# Entry toolbar: render one time, drive with Stimulus

- Date: 2026-10-12
- Branch: `entry-toolbar-once`
- Status: draft for review

## Why

Today the server renders a full copy of the entry toolbar for each entry. The preload endpoint (`GET /entries/preload`) sends that copy in the `content` key of each entry, next to `inner_content`. Almost all of the toolbar is the same for every entry.

Measured on the dev database (user 1, the 100 newest entries, one preload batch):

| | Now | After (estimate) |
|---|---|---|
| Toolbar render | 87 ms | about 5 ms (favicon fragments only) |
| Content render | 220 ms | 220 ms (no change) |
| JSON, raw | 1,248 KB | about 620 KB |
| JSON, gzip | 114 KB | about 93 KB |

Dev content is mostly short podcast notes, so production content makes the content render larger. The toolbar cost does not depend on the content.

The browser also does less work. When the entry changes, the browser does not replace the toolbar DOM, and no inline `<script>` runs.

Ben decided:

1. The server renders the toolbar one time, in the page.
2. The toolbar does not use Rails forms. JavaScript drives it.
3. The JavaScript is a Stimulus controller.
4. The server still renders the favicon for each entry, as a small HTML fragment. `FaviconComponent` needs server data: image rows, the Pages favicon of each host, and the channel avatar of a playlist video. So that logic stays in one place.

## Goals

1. One toolbar element exists in the page for the whole session.
2. The preload response holds a small toolbar data object for each entry, in place of the toolbar HTML.
3. A Stimulus controller fills the toolbar from the toolbar data when an entry opens. The controller sends all toolbar requests.
4. No Rails form and no `data-remote` form stays in the toolbar.
5. Every current toolbar behavior and keyboard shortcut works as before.

## Non-goals

- No change to how the toolbar looks.
- No change to the content render (`entries/_inner_content`). The ContentFormatter cache is a separate project.
- No change to the Edit Subscription dialog. It keeps its remote link and its `subscriptions/edit.js.erb` response, because many other links use the same dialog code.
- No change to the account toolbar (`.account-toolbar`).
- No new error handling. Star and read stay optimistic and do not revert on failure, as today.

## Anti-goals

The work fails if one of these occurs, even if all else works:

- A toolbar action applies to an entry that is not the entry on screen. This includes star, read, extract, and delete.
- A browser tab that loaded the old JavaScript breaks, or acts on the wrong entry, after the deploy. See "Old tabs".
- A keyboard shortcut stops.

## Terms

- **Toolbar data**: the object for each entry that replaces the `content` key. "Server changes" lists its fields.
- **URL template**: a path that the server renders one time, with a placeholder for the entry id or the feed id. The controller replaces the placeholder.
- **Old tab**: a browser tab that loaded the page before the deploy. It runs the old JavaScript until the user reloads it.

## Current behavior

All of this must still work after the change.

The toolbar is `entries/_show.html.erb`. Each time an entry opens, `feedbin.updateEntryContent` puts it into `[data-behavior~=entry_meta_target]`. Its parts:

| Part | Today | Changes per entry |
|---|---|---|
| Back and full screen buttons | `show_entries_panel` and `full_screen` behaviors | No |
| Header: favicon and feed title | `EntryPresenter#feed_wrapper`, `#favicon`, `#entry_header_title` | Yes |
| Header link to Edit Subscription | `link_to edit_subscription_path(feed, app: true), remote: true` with `data-open-dialog`. Only when the user subscribes to the feed and the feed is not Pages. Else a `<span>`. | Yes |
| Delete | `entries/_delete_button`: a remote `DELETE` form with `data-confirm`, only for Pages entries. The response is `entries/destroy.js.erb`. | Yes |
| Share | `sharing_services/_sharing_service_button`. `feedbin.prepareShareMenu(data)` fills the menu. | The menu items |
| Extract | `entries/_toggle_content`: a remote `GET` form to `/extracts/:id/entry`. The handlers are in `updateReadability` in `_site.js.coffee`. The response is `extracts/entry.js.erb`. | Yes |
| Star | `starred_entries/_form`: a remote `POST /entries/:id/starred_entries`. `CountsBehavior#toggleStarred` changes the counts on `ajax:beforeSend`. | Yes |
| Read | `unread_entries/_form`: a remote `POST /entries/:id/unread_entries`. `CountsBehavior#toggleRead` changes the counts. | Yes |
| Format and settings | `shared/_entry_settings_button`, `shared/_app_settings` | No |
| Copy-link field | a hidden `textarea#source_link_field` with the entry URL, for the `C` shortcut | Yes |
| Inline script | sets `feedbin.selectedEntryData`, then calls `prepareShareMenu` and `faviconColors` | Yes |

Code that reaches into the toolbar today:

1. `keyboard.js.coffee`: `s`, `m`, and `c` call `.submit()` on the star, read, and extract forms. `f` clicks `[data-behavior~=toggle_share_menu]`. `C` copies `#source_link_field`.
2. `feedbin.readability()` submits the extract form when the feed has sticky extract on. First it sets `feedbin.automaticSubmit = true`. The flag stops the extract handler from a `POST` to the sticky URL.
3. `feedbin.readabilityActive()` reads the `.active` class of the extract button. `prepareShareForm` and the `needs_extract` share links use it.
4. `feedbin.formatEntryContent` aborts `feedbin.readabilityXHR`. It also calls `feedbin.applyStarred`, which adds `.starred` to `[data-behavior~=selected_entry_data]`.
5. `CountsBehavior#mark` and `#unmark` add or remove `.read` and `.starred` on every `[data-entry-id=ID]`. The toolbar forms carry `data-entry-id`, so the star and read buttons get their state this way today.
6. The extract handler sends a `POST` to `settings_sticky_path(feed_id)`. The response, `settings/sticky.js.erb`, updates `feedbin.data.readability_settings`. jQuery runs the response because its content type is JavaScript.
7. `feedbin.updateEntryContent('')` clears the entry. `clearEntry`, `saved_searches/destroy.js.erb`, and `tags/destroy.js.erb` call it.
8. `.entry-meta` shows only when `.entry-column` has `.has-content`. So the toolbar hides when no entry is open.

## Design

### Markup: `App::EntryToolbarComponent`

Claude's call: a Phlex component, because new UI code in this app uses Phlex with Stimulus. For the pattern, see `app/views/components/dialog/add_feed.rb` with `add_feed_controller.js`, and the `stimulus` and `stimulus_item` helpers in `ApplicationComponent`.

- `logged_in.html.erb` renders the component one time, inside `[data-behavior~=entry_meta_target]`.
- The markup classes stay the same as in `entries/_show.html.erb`: `.toolbar-wrap`, `.entry-toolbar`, `.site-info`, `.entry-buttons`, `.entry-button-wrap`, and the `.button-toggle-*` classes. Then the current SCSS still applies.
- The root element is the controller root, with `STIMULUS_CONTROLLER = :entry_toolbar` (identifier `entry-toolbar`). The current `toolbar` controller, which hides the toolbar on scroll, is a different controller. The share button keeps its `click->toolbar#show` action.
- The root holds the URL templates as Stimulus values:
  - star: `starred_entries_entry_path(ID)`
  - read: `unread_entries_entry_path(ID)`
  - extract: `entry_extract_path(ID)`
  - delete: `entry_path(ID)`
  - sticky: `settings_sticky_path(FEED_ID)`
  - edit subscription: `edit_subscription_path(FEED_ID, app: true)`
- The star, read, extract, and delete buttons are `<button type="button">` elements with Stimulus actions.
- The format, settings, share, back, and full screen buttons keep their current `data-behavior` hooks. Their code does not change.
- The component keeps one copy-link field for the `C` shortcut. Claude's call: then the shortcut code does not change.
- The favicon and the title are targets that the controller fills.

### State

The controller root holds the state of the open entry as Stimulus values:

| Value | Type | Source |
|---|---|---|
| `entryId` | Number | toolbar data. `0` when no entry is open. |
| `feedId` | Number | toolbar data |
| `starred` | Boolean | `feedbin.Counts` on open, and after each star toggle |
| `read` | Boolean | `true` on open, as today, because the entry is marked read when it opens. `feedbin.Counts` after each read toggle. |
| `extract` | Boolean | `false` on open. `true` while the extracted view shows. |
| `loading` | Boolean | `true` while an extract request runs |
| `pages` | Boolean | toolbar data. Shows the delete button. |
| `subscribed` | Boolean | toolbar data. Makes the header a link. |

CSS reads these values from their data attributes. JavaScript does not add or remove the state classes. This is the `add_feed` pattern. The SCSS selectors for the toolbar buttons that use `.read &`, `.starred &`, `.active`, and `.loading` change to selectors on the value attributes, for example `[data-entry-toolbar-starred-value="true"]`.

### Open an entry

`feedbin.showEntry(entryId)` sends the toolbar data to the controller **before** it calls `feedbin.formatEntryContent`. The order is important. `formatEntryContent` calls `feedbin.readability()`, and that call can start an automatic extract for the new entry. Claude's call: a window event, for example `entry-toolbar:show`, with the toolbar data as `detail`. The app already uses window events such as `show-entry`.

When an entry opens, the controller does these steps:

1. Set the values in the State table.
2. Put the favicon fragment into the favicon target. Call `feedbin.faviconColors` on the toolbar.
3. Set the title. For a feed that is not Pages, use `feedbin.data.user_titles[feed_id]` if it exists. Else use `header_title`.
4. If `subscribed` is true, make the header a link to Edit Subscription. Else the header is not a link: it has no `href`, no tooltip, and no hover style, and it does not open a dialog.
5. Set the copy-link field to the entry URL.
6. Set `feedbin.selectedEntryData` to the toolbar data. The mute form and `prepareShareForm` read it.
7. Call `feedbin.prepareShareMenu(toolbarData)`.
8. Close the share dropdown if it is open. Today the dropdown closes because the old toolbar leaves the DOM.

For a feed that is not Pages, the title element keeps `data-behavior="user_title"` and the current `data-feed-id`. Then `feedbin.applyUserTitles(false)` still renames the header when the user renames the feed.

**Caution:** jQuery `.data()` caches each `data-*` value the first time it reads it. `applyUserTitles` reads `data-feed-id` with `.data('feed-id')`. If the title element stays and only its attribute changes, jQuery gives the old feed id. The builder must prevent this. One way is to replace the title element each time an entry opens. Another way is to call `$(element).removeData()` after the change.

`feedbin.applyStarred` and `[data-behavior~=selected_entry_data]` go away, because the controller sets `starred`.

`feedbin.updateEntryContent` no longer receives toolbar HTML. A call with no entry still hides the toolbar through `.has-content`. That call also sets `entryId` to `0`.

### Requests

The controller sends every request with `@rails/request.js` (the `requestjs-rails` gem; Ben decided this after the first build). It sends the CSRF token from `<meta name="csrf-token">` and `X-Requested-With`, and `responseKind` sets the `Accept` header. It does not throw on an HTTP error, so the controller checks `response.ok`. The system tests count fetch requests in the Cuprite driver, not in app code.

Each request builds its URL from the template and from the entry id or feed id at the time the request starts. A response for an entry that is no longer open must not change the screen.

A toolbar action does nothing when `entryId` is `0`.

**Star** (the button, the `s` key):

1. Change the counts and the entry list classes as `CountsBehavior#toggleStarred` does today. This is a `Counts` add or remove, `feedbin.applyCounts(true)`, and `.starred` on the list item `[data-entry-id=ID]`.
2. Set `starred` from `feedbin.Counts`.
3. Send a `POST` to the star URL. The server toggles the star. The response is `200` with no body, as today.

**Read** (the button, the `m` key): the same steps as star, with `CountsBehavior#toggleRead`, the `unread` count, `read`, and the read URL. Keep the special case in `CountsBehavior#unmark` for the `updated` collection.

Today nothing holds a reference to the `CountsBehavior` object (`new feedbin.CountsBehavior()` in `_site.js.coffee`). The builder makes the toggle logic available to the controller. The builder also removes the `ajax:beforeSend` hooks for the old star and read forms.

**Extract** (the button, the `c` key, and automatic from `feedbin.readability()`):

Do these steps in this order. Steps 2 to 5 are alternatives: do the first one that matches.

1. If the press is not automatic, send a `POST` to the sticky URL. Then set `feedbin.data.readability_settings[feedId]` from the response. See "Server changes". Every manual press sends this `POST`, as today. An automatic press does not. An event detail, for example `{automatic: true}`, replaces the `feedbin.automaticSubmit` flag.
2. If an extract request runs (`loading` is true): abort it. Set `loading` and `extract` to false. Call `feedbin.changeContentView('default')`. This is the behavior of today.
3. If `extract` is true: set `extract` to false. Call `feedbin.changeContentView(feedbin.previousContentView)`. Send no request. This is Claude's call. Today, after a failed request, a second press can send `extract=false`, and the server then puts the original content into the extract slot. That path goes away.
4. If `feedbin.extractCache[entryId]` exists: put it into `[data-entry-id=ID] [data-content-option=extract]`. Call `feedbin.formatEntryContent(entryId, false, false)` and `feedbin.changeContentView('extract')`. Set `extract` to true.
5. Else: set `loading` and `extract` to true. Send a `GET` to the extract URL with `extract=true`.
   - On success, set `loading` to false. Then do what `extracts/entry.js.erb` does today:
     1. Store the HTML in `feedbin.extractCache`.
     2. Put it into the extract slot.
     3. Call `feedbin.changeContentView('extract')`.
     4. Call `feedbin.formatEntryContent(id, false, false)`.
     5. Call `feedbin.entryTime()`.
   - On failure, set `loading` and `extract` to false. Call `feedbin.changeContentView('default')`. This is Claude's call. Today a failure leaves the button active with no extracted content.
   - After an abort, do nothing. Step 2 or the open of another entry already set the state.

When another entry opens, `feedbin.formatEntryContent` aborts `feedbin.readabilityXHR`. The controller stores its `AbortController` in `feedbin.readabilityXHR`, because an `AbortController` also has an `abort()` method. The controller also sets `loading` to false when another entry opens.

`feedbin.readabilityActive()` returns the `extract` value of the toolbar.

**Delete** (Pages entries only):

1. Call `confirm("Are you sure you want to delete this page?")`. If the user cancels, stop.
2. Send a `DELETE` to the delete URL.
3. On success, do what `entries/destroy.js.erb` does today:
   1. Remove the list item from `[data-behavior~=entries_target]`.
   2. Remove the entry from the `unread` and `starred` counts.
   3. Call `feedbin.applyCounts(true)`, `feedbin.clearEntry()`, and `feedbin.fullScreen(false)`.

**Edit Subscription**: the header link keeps the mechanism of today. It is a jQuery UJS remote link with `data-open-dialog`, and the response is `subscriptions/edit.js.erb`. The controller sets its `href` from the template. Note: jQuery UJS ignores `a[data-remote][disabled]`, but the `[data-open-dialog]` click handler in `_site.js.coffee` does not check `disabled`.

### Keyboard shortcuts

- `s`, `m`, and `c` send window events, for example `entry-toolbar:star`. The controller listens with `@window` actions.
- `f`, `C`, and the share number keys do not change.

### Server changes

1. `EntriesController#entries_by_id` builds the toolbar data in place of the `entries/show` render:

   ```ruby
   toolbar: {
     id: entry.id,
     feed_id: entry.feed_id,
     url: entry.fully_qualified_url,
     title: entry.title,
     feed_title: entry.feed.title, # ${source} in the share menu
     twitter_id: entry.twitter_id || "",
     header_title: entry.feed.pages? ? entry.hostname : strip_tags(entry.feed.title),
     pages: entry.feed.pages?,
     subscribed: !entry.feed.pages? && subscriptions.include?(entry.feed_id),
     favicon: # FaviconComponent HTML for entry.feed and entry
   }
   ```

   `inner_content` and `feed_id` do not change. The first six fields are the fields of `feedbin.selectedEntryData` today.

   Claude's call: load the favicon data for a batch in a fixed number of queries. Pass `Image.favicons_for_entries(entries)` to `FaviconComponent` as `favicons:`, and preload `channel_image_record` on the entries. Today each Pages entry and each playlist video does its own query.

2. `ExtractsController#entry` responds to HTML with the `extracts/_entry` partial, with no layout.
3. `EntriesController#destroy` responds with `204 No Content`.
4. `SettingsController#sticky` responds to JSON with `{view_inline: true}` or `{view_inline: false}`. When the user has no subscription to the feed, it responds with `204`, and the controller changes nothing.
5. `site/logged_in.html.erb` renders the toolbar component. Its inline script calls `feedbin.showEntry` on a full page load of `/entries/:id`. That script must work with the new data shape.
6. The entry list, `inner_content`, and the routes do not change.

### Old tabs

Feedbin users keep tabs open for days, and the app does not reload a tab after a deploy. An old tab with the new server is dangerous. The old `showEntry` calls `metaTarget.html(undefined)`, and jQuery treats that call as a read. So the old toolbar stays on screen, with the forms of the **previous** entry. A star or a delete then goes to the wrong entry. This is an anti-goal.

Claude's call: ship in two steps.

**Step 1 (this branch)**: the server answers the old JavaScript and the new JavaScript.

| Request | From an old tab | From the new JavaScript | Step 1 response |
|---|---|---|---|
| `GET /entries/preload` | the path in its own `feedbin.data` | a new `preload_entries_path` with a version parameter, for example `v=2` | With the parameter: toolbar data, no `content`. Without it: `content`, as today. |
| `GET /entries/:id`, JS | the entry list link | the same link | Both `content` and `toolbar`. It is one entry, so the cost is small. |
| `GET /entries/:id`, HTML | not possible | a full page load | Toolbar data, no `content` |
| `GET /extracts/:id/entry` | `Accept: text/javascript` | `Accept: text/html` | `respond_to`: JS gets `entry.js.erb`. HTML gets the partial. |
| `DELETE /entries/:id` | JS | `@rails/request.js` | `respond_to`: JS gets `destroy.js.erb`. Other formats get `204`. |
| `POST /settings/sticky/:feed_id` | `$.post` with `Accept: */*` | `Accept: application/json` | `respond_to`: JSON gets JSON. Other formats get `sticky.js.erb`. For `*/*`, Rails uses the first format in the block, so put JS first. |

**New JavaScript with an old server.** During a deploy, app hosts can run old code and new code at the same time for a short period. A page from a new host can send its preload to an old host. The old host ignores the version parameter and returns `content` with no `toolbar`. Claude's call, these rules apply:

1. `feedbin.preloadEntries` treats a cached entry with no `toolbar` as not cached. A later preload then fetches that entry again.
2. If `feedbin.showEntry` gets an entry with no `toolbar`, the content still shows, and the controller sets `entryId` to `0`. Then no toolbar action can apply to the wrong entry.
3. An extract request to an old host fails. The failure rule in "Extract" applies.

**Native app.** The iOS and macOS wrapper (`~/Sites/feedbin-ios`) runs only `feedbin.baseFontSize(...)` and triggers the `feedbin:native:statusbartouched` and `feedbin:native:userchangedtextsize` events. It does not touch the toolbar, so it needs no compatibility hooks.

In step 1, the old partials and the JS templates stay, but only old-tab requests use them. The old partials are `entries/_show`, `entries/_delete_button`, `entries/_toggle_content`, `starred_entries/_form`, and `unread_entries/_form`.

**Step 2 (a later change, when Ben decides that the old tabs are gone)**: remove the `content` key, the version parameter, the JS formats in the table, and the old partials. Keep `shared/_app_settings`, because the account toolbar uses it.

## Tests

Write each test before the code. Make sure that the test fails before the code exists.

Controller tests:

1. Preload with the version parameter: each entry has `toolbar` with all its fields, and no `content`. The `pages` and `subscribed` flags are correct for a Pages entry, for a subscribed feed, and for a feed with no subscription. An example of the last case is a starred entry from a feed that the user left.
2. Preload without the version parameter: each entry still has `content`. This test goes away in step 2.
3. Preload uses a fixed number of favicon queries for a batch with Pages entries from more than one host.
4. The HTML response of `extracts#entry` holds the partial. The JS response does not change.
5. `entries#destroy` gives `204` for a request that is not JS. The JS response does not change.
6. The JSON response of `settings#sticky` holds `view_inline`.
7. Replace the test "preload renders a settings button, not the settings menu" in `entries_controller_test.rb`. The new test makes sure that the page renders one settings menu, and that preload holds no toolbar HTML.

System tests, in `test/system/article_test.rb`:

1. Star and unstar with the button and with `s`. `StarredEntry.count` changes, and the button shows the state.
2. Mark unread with the button and with `m`.
3. Extract with the button and with `c`. A second press shows the original content and sends no extract request. A press while the extract request runs aborts it and shows the original content.
4. Automatic extract for a feed with sticky extract on. The sticky setting does not change.
5. Open entry A, then entry B. The header shows the title and favicon of B. A star then applies to B. The page has one `.entry-toolbar`.
6. Open entry A. Open the share menu. Open entry B. The share menu is closed.
7. Delete a Pages entry and accept the confirm. The list item goes away, and the entry clears.
8. The header of a subscribed feed opens Edit Subscription. The header of a feed with no subscription is not a link.
9. A full page load of `/entries/:id` shows the toolbar for that entry.
10. Rename a feed while one of its entries is open. The header shows the new title.
11. Update the current tests that use the old form selectors, for example `[data-behavior~=toggle_starred]` and `.starred` on the form.
12. Open an entry that has no `toolbar` in `feedbin.entries`, for example with a script that removes the key. The content shows, and the star, read, extract, and delete actions send no request.

After the build, run the preload measurement again. For a batch of 100 entries, the toolbar part must be about 5 ms or less, and the raw JSON about half its current size.

Test notes for this app:

- `rails test:system` ignores `TEST=`. Use `bin/rails test test/system/article_test.rb`.
- `public/assets` and `tmp/cache/assets` can serve old JavaScript to system tests.
- Tests do not run in the sandbox, because `bind(2)` fails with `EPERM`.

## Left to the builder

- The placeholder text in the URL templates, and the names of the values, targets, and events.
- How the header stops being a link when `subscribed` is false.
- The copy-link field, or `navigator.clipboard` in its place.
- How `CountsBehavior` makes its toggle logic available.
- SCSS or Tailwind `group-data-[...]` for each state selector.
- The name of the version parameter.
- The new signature of `updateEntryContent`, and whether its three callers with `''` change to `feedbin.clearEntry()`.
