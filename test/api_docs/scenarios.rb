# Per-page setup beyond ApiDocs::World, keyed by path under _endpoints/. Blocks
# run inside the rolled-back transaction; network is blocked, so stub it here.
module ApiDocs
  scenario "entries/list", per_source: true do |source|
    UnreadEntry.where(user_id: 1).where.not(entry_id: source["entry_id"]).delete_all
    entry = Entry.find(source["entry_id"])
    UnreadEntry.create_from_owners(World.current_user, entry) unless UnreadEntry.exists?(user_id: 1, entry_id: entry.id)
  end

  scenario "feeds/entries", per_source: true

  # Recently looked up, so the lookup doesn't refetch the feed.
  scenario "feeds/lookup" do
    Feed.where(id: 2210).update_all(standalone_request_at: NOW - 10.minutes)
  end

  # An empty Airshow, so the episodes go in.
  scenario "collections/add" do
    QueuedEntry.where(user_id: 1).delete_all
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

  # A proposal's digits are random and its signature uses the machine's
  # secret_key_base, so both are fixed.
  ADDRESS_VERIFIER = ActiveSupport::MessageVerifier.new("docs-address-token-secret")
  fixed_address = ->(request) {
    AuthenticationToken.stub(:address_verifier, ADDRESS_VERIFIER) do
      AuthenticationToken.stub(:generate_custom_token, "ac.522") { request.call }
    end
  }
  # The state is signed with an expiry, so the page the app opens is fixed.
  scenario "share_services/authorize", around: ->(request) {
    url = "https://www.instapaper.com/oauth2/authorize?client_id=feedbin&redirect_uri=https%3A%2F%2Ffeedbin.com%2Fsupported_sharing_services%2Finstapaper%2Foauth2_response&response_type=code&state=eyJfcmFpbHMiOnsiZGF0YSI6eyJ1c2VyX2lkIjoxfX19--4f1c"
    ShareAuthorization.stub(:start, url) { request.call }
  }

  # The replacement runs in the background; the answer is the item waiting for it.
  in_background = ->(request) { Sidekiq::Testing.fake! { request.call } }
  scenario "imports/replace", around: in_background
  scenario "imports/replace_all", around: in_background

  scenario "newsletters/propose", around: fixed_address
  scenario "newsletters/create", around: fixed_address

  # Object pages request every expansion.
  object "account", "/account"
  object "action", "/actions", pick: "data/0"
  object "attachment", "/entries?ids=2947218", pick: "data/0/attachments"
  object "collection", "/collections"
  object "feed", "/subscriptions/new", method: :post, body: {q: "daring fireball"}.to_json, pick: "data/0"
  object "image", "/entries?ids=2947218", pick: "data/0/images/preview"
  object "import", "/imports/3310"
  object "share-service", "/share_services", pick: "data/1"
  object "custom-share-service", "/custom_share_services", pick: "data/0"
  object "newsletter-address", "/newsletters/addresses", pick: "data/1"
  object "newsletter-sender", "/newsletters/senders", pick: "data/0"
  object "playlist", "/playlists", pick: "data/0"
  object "saved-search", "/saved_searches", pick: "data/0"
  object "subscription", "/subscriptions/525?expand=feed,tags"
  object "tag", "/tags", pick: "data/0"
  object "token", "/tokens", pick: "data/0"
  object "video", "/entries?ids=2948530", pick: "data/0/videos/0"

  # Read from Airshow's queue so the entry carries collection membership.
  object "entry", "/collections/queue/entries?expand=feed,changes,original_newsletter", per_source: true, pick: "data/0" do |source|
    QueuedEntry.where(user_id: 1).delete_all
    entry = Entry.find(source["entry_id"])
    QueuedEntry.create!(user_id: 1, entry_id: entry.id, feed_id: entry.feed_id, order: 0, progress: 1204, duration: 6412,
      playlist_id: 2, created_at: Time.utc(2026, 9, 8, 14, 2, 11), updated_at: Time.utc(2026, 9, 8, 14, 2, 11))
  end

  # Snippets for prose.
  snippet "envelope", "/entries?limit=2"
  snippet "entries-by-id", "/entries?ids=2947218,2946102,2940771"
  snippet "state-scope", "/entries/state", method: :post, body: {mark_read: {feed_ids: [1356, 2210], published_before: "2026-09-09T00:00:00Z"}}.to_json

  # Problems. The docs quote these rather than typing an error out.
  snippet "unauthorized", "/entries", status: 401, authenticated: false
  snippet "cursor-invalid", "/entries?cursor=zz", status: 400
  snippet "validation-failed", "/playlists/2", method: :patch, status: 422, body: {title: "Road trips"}.to_json
  snippet "upstream-error", "/subscriptions/new", method: :post, status: 422, body: {q: "https://example.com/feed"}.to_json do
    stub_request(:get, "https://example.com/feed").to_return(status: 404)
  end
end
