# What each docs page needs beyond ApiDocs::World, keyed by the page's path
# under _endpoints/, and the request each object page's example comes from.
# A block runs in the test, before the request, inside the transaction that
# rolls back after it. Network access is blocked, so a page that reaches
# out needs its stub here.
module ApiDocs
  # The unread timeline shows one source's entry at a time, as the example
  # switcher presents it.
  scenario "entries/list", per_source: true do |source|
    UnreadEntry.where(user_id: 1).where.not(entry_id: source["entry_id"]).delete_all
    entry = Entry.find(source["entry_id"])
    UnreadEntry.create_from_owners(World.current_user, entry) unless UnreadEntry.exists?(user_id: 1, entry_id: entry.id)
  end

  scenario "feeds/entries", per_source: true

  # Looked up recently, so the lookup serves what Feedbin has instead of
  # fetching the feed again.
  scenario "feeds/lookup" do
    Feed.where(id: 2210).update_all(standalone_request_at: NOW - 10.minutes)
  end

  # An empty Airshow, so the episodes go in.
  scenario "collections/add" do
    QueuedEntry.where(user_id: 1).delete_all
  end

  # Find feeds offered both feeds, so Subscribe takes the one the user
  # can't otherwise read.
  scenario "subscriptions/create" do
    Api::V3::Subscribe.offer(World.current_user, Feed.where(id: [1356, 1357]).to_a)
  end

  # A page not saved before, so the response is the 201 a new save gets.
  scenario "pages/create" do
    Entry.where(id: 2951002).delete_all
    stub_request(:get, %r{\Ahttps://extract\.feedbin\.com/parser/}).to_return(headers: {"Content-Type" => "application/json"}, body: {
      title: "A Long Read", author: nil, url: "https://example.com/long-read", domain: "example.com",
      content: "<p>The page as Feedbin extracted it when it was saved.</p>", date_published: nil, lead_image_url: nil
    }.to_json)
  end

  scenario "account/purchases" do
    product_id = Feedbin::Application.config.iap.keys.first
    stub_request(:post, "https://buy.itunes.apple.com/verifyReceipt").to_return(headers: {"Content-Type" => "application/json"}, body: {
      status: 0,
      receipt: {in_app: [{transaction_id: "2000000712345678", product_id: product_id, purchase_date_ms: NOW.to_i * 1_000}]}
    }.to_json)
  end

  scenario "imports/create", request: ->(_source) {
    {content_type: "text/x-opml", body: <<~OPML}
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0">
        <head><title>Subscriptions</title></head>
        <body>
          <outline text="Daring Fireball" title="Daring Fireball" type="rss" xmlUrl="https://daringfireball.net/feeds/main" htmlUrl="https://daringfireball.net"/>
          <outline text="Old Blog" title="Old Blog" type="rss" xmlUrl="https://example.com/rss" htmlUrl="https://example.com"/>
        </body>
      </opml>
    OPML
  }

  # Object pages. Each shows every field the object can have, so its
  # request asks for every expansion.
  object "account", "/account"
  object "action", "/actions", pick: "data/0"
  object "attachment", "/entries?ids=2947218", pick: "data/0/attachments"
  object "collection", "/collections"
  object "feed", "/subscriptions/new", method: :post, body: {q: "daring fireball"}.to_json, pick: "data/0"
  object "image", "/entries?ids=2947218", pick: "data/0/images/preview"
  object "playlist", "/playlists", pick: "data/0"
  object "saved-search", "/saved_searches", pick: "data/0"
  object "subscription", "/subscriptions/525?expand=feed,tags"
  object "tag", "/tags", pick: "data/0"
  object "token", "/tokens", pick: "data/0"
  object "video", "/entries?ids=2948530", pick: "data/0/videos/0"

  # An entry with everything: its feed, both optional bodies, and the
  # membership a collection read adds, from Airshow's queue.
  object "entry", "/collections/queue/entries?expand=feed,changes,original_newsletter", per_source: true, pick: "data/0" do |source|
    QueuedEntry.where(user_id: 1).delete_all
    entry = Entry.find(source["entry_id"])
    QueuedEntry.create!(user_id: 1, entry_id: entry.id, feed_id: entry.feed_id, order: 0, progress: 1204, duration: 6412,
      playlist_id: 2, created_at: Time.utc(2026, 9, 8, 14, 2, 11), updated_at: Time.utc(2026, 9, 8, 14, 2, 11))
  end

  # Snippets for prose. The envelope, on conventions.md: a timeline page
  # with a next page. Lookup by id, on List entries: one id the user can't
  # read.
  snippet "envelope", "/entries?limit=2"
  snippet "entries-by-id", "/entries?ids=2947218,2946102,2940771"
end
