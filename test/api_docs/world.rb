module ApiDocs
  # The docs' fake account, built from _data/examples/sources.yml. Explicit
  # ids and timestamps keep examples identical across runs.
  module World
    IMAGE_HOST = "https://images.feedbin.com"

    module_function

    # Afterwards each table's next id follows its highest example id.
    def build
      Sequences.reset(start: Sequences::WORLD)
      user
      sources
      daring_fireball_articles
      tags
      token
      states
      collections
      account_extras
      index
      Sequences.reset
    end

    def user
      User.insert!({
        id: 1,
        email: "ben@example.com",
        password_digest: BCrypt::Password.create("password", cost: BCrypt::Engine::MIN_COST),
        plan_id: Plan.find_by!(stripe_id: "basic-yearly-3").id,
        price_tier: 3,
        auth_token: "docs-auth-token",
        page_token: "7f3a1c9e42b8d0574a61",
        newsletter_token: "x7k2",
        settings: {"api_v3" => "1", "podcast_download_limit" => "10", "hide_airshow" => "0", "hide_recently_played" => "1"},
        expires_at: Time.utc(2027, 3, 1),
        created_at: Time.utc(2012, 11, 14, 2, 10, 55),
        updated_at: Time.utc(2012, 11, 14, 2, 10, 55)
      })
      @user = User.find(1)
      AuthenticationToken.create!(user: @user, token: "ben.x7k2", purpose: :newsletters)
    end

    def current_user = User.find(1)

    def sources
      daring_fireball
      atp
      mkbhd
      platformer
      marco
      pages
    end

    def daring_fireball
      feed = feed!(
        id: 1356, title: "Daring Fireball", feed_url: "https://daringfireball.net/feeds/main",
        site_url: "https://daringfireball.net", host: "daringfireball.net",
        options: {"description" => "By John Gruber"}, last_published_entry: Time.utc(2026, 9, 8, 21, 40, 2)
      )
      site_icons(feed,
        favicon: {path: "b8c/b8c5c3277737475990b404fabcc4ece8.png", bytes: 1204, color: "4a4a4a", url: "https://daringfireball.net/favicon.ico", fingerprint: "08e3bbf80dd9b8fa68501170da0551e4"},
        touch_icon: {path: "605/6052d2af172fb1f3294a5f6a89a89d4e.png", bytes: 9110, color: "4a4a4a", url: "https://daringfireball.net/graphics/apple-touch-icon.png", fingerprint: "be06779c3c7401c9f74cedaac26512a5"})
      subscription!(id: 525, feed: feed, created_at: Time.utc(2019, 2, 3, 22, 8, 31), show_updates: true)
      entry = entry!(
        id: 2945880, feed: feed, title: "The Grand Unified Timeline", author: "John Gruber",
        summary: "A short piece about why the schedule slipped, and what that says about the next one.",
        url: "https://daringfireball.net/2026/09/the_grand_unified_timeline",
        content: "<p>A short piece about why the schedule slipped, and what that says about the next one.</p>",
        published: Time.utc(2026, 9, 4, 4, 30), created_at: Time.utc(2026, 9, 4, 4, 31, 12),
        revision: 3, edited_at: Time.utc(2026, 9, 4, 6, 2, 44)
      )
      image!(:entry_preview, entry.id, feed: feed, kind: :poster, path: "370/370319459194d93d68a007eeb967123c.jpg",
        width: 542, height: 304, bytes: 48211, color: "22436a",
        url: "https://daringfireball.net/graphics/2026/09/timeline.png", fingerprint: "8ff083aece99cce1a46c3e79fe950b9d")
    end

    def atp
      feed = feed!(
        id: 2210, title: "Accidental Tech Podcast", feed_url: "https://atp.fm/rss",
        site_url: "https://atp.fm", host: "atp.fm",
        options: {"description" => "Three nerds discussing tech, Apple, programming, and loosely related matters."},
        last_published_entry: Time.utc(2026, 9, 4, 4, 30)
      )
      site_icons(feed,
        favicon: {path: "0b7/0b7fec786e02cbae20bc47fdde59e311.png", bytes: 989, color: "101418", url: "https://atp.fm/favicon.ico", fingerprint: "081c95926a68b9b3ca691e01f2af5725"})
      image!(:feed_icon, feed.id, feed: feed, kind: :cover_art, path: "009/009893fc67bcd74611149c0f399c5784.jpg",
        width: 200, height: 200, bytes: 18022, color: "101418",
        url: "https://atp.fm/assets/artwork-1400.jpg", fingerprint: "17903ce7ed0b511144f3bad15b4e2e45")
      subscription!(id: 771, feed: feed, title: "ATP", created_at: Time.utc(2021, 6, 18, 11, 30, 2), media_only: true, show_updates: false)
      entry = entry!(
        id: 2947218, feed: feed, title: "412: The Grand Unified Timeline", author: "Accidental Tech Podcast",
        summary: "John finds a filesystem, Marco ships a beta, and Casey explains why none of it matters until the timeline lines up.",
        url: "https://atp.fm/412",
        content: "<p>John finds a filesystem, Marco ships a beta, and Casey explains why none of it matters until the timeline lines up.</p>",
        published: Time.utc(2026, 9, 4, 4, 30), created_at: Time.utc(2026, 9, 4, 4, 31, 12),
        revision: 3, edited_at: Time.utc(2026, 9, 4, 6, 2, 44),
        categories: ["Technology"],
        data: {"enclosure_url" => "https://cdn.atp.fm/episodes/412.mp3", "enclosure_type" => "audio/mpeg", "enclosure_length" => "43018332", "itunes_duration" => "1:46:52"},
        chapters: [{"start_time" => "0", "tags" => {"title" => "Follow-up"}}, {"start_time" => "812.5", "tags" => {"title" => "Filesystems"}}]
      )
      entry!(
        id: 2946102, feed: feed, title: "411: Swift on the Server", author: "Accidental Tech Podcast",
        summary: "Casey tries server-side Swift, John reviews a keyboard, and Marco finally replaces his router.",
        url: "https://atp.fm/411",
        content: "<p>Casey tries server-side Swift, John reviews a keyboard, and Marco finally replaces his router.</p>",
        published: Time.utc(2026, 8, 28, 4, 12), created_at: Time.utc(2026, 8, 28, 4, 13, 40),
        categories: ["Technology"],
        data: {"enclosure_url" => "https://cdn.atp.fm/episodes/411.mp3", "enclosure_type" => "audio/mpeg", "enclosure_length" => "41207719", "itunes_duration" => "1:42:15"}
      )
      image!(:entry_preview, entry.id, feed: feed, kind: :poster, path: "33b/33b2c4f367102ceae5e26321cd85b34c.jpg",
        width: 542, height: 304, bytes: 48211, color: "22436a",
        url: "https://atp.fm/assets/412-cover.jpg", fingerprint: "4c2ce35ce3e1b1bdc31621ae06638d9c")
    end

    CHANNEL_ID = "UCBJycsmduvYEL83R_U4JriQ"
    VIDEO_ID = "Hq8Xw2Lk5dA"

    def mkbhd
      feed = feed!(
        id: 3021, title: "Marques Brownlee", feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{CHANNEL_ID}",
        site_url: "https://www.youtube.com/channel/#{CHANNEL_ID}", host: "www.youtube.com", channel_id: CHANNEL_ID,
        options: {"description" => "Quality tech videos."}, last_published_entry: Time.utc(2026, 9, 7, 16, 0, 12)
      )
      site_icons(feed,
        favicon: {path: "20d/20d6101b21c748ad0cb05cdfd55dd027.png", bytes: 1150, color: "ff0033", url: "https://www.youtube.com/favicon.ico", fingerprint: "0177fe713fb7428620f8f082c1ee8f01"},
        touch_icon: {path: "536/536ed88c737ed8fc6b09ae3988586c5d.png", bytes: 7412, color: "ff0033", url: "https://www.youtube.com/s/desktop/apple-touch-icon.png", fingerprint: "b63f8b73ea419ae3c0012342145247ca"})
      image!(:embed_icon, CHANNEL_ID, feed: nil, kind: :avatar, path: "e5c/e5cd66496868eb2b3a25680f1a835d76.png",
        width: 200, height: 200, bytes: 21406, color: "1d1d1d",
        url: "https://yt3.googleusercontent.com/lkH37D712tiyphnu0Id0D5MwwQ7IRuwgQLVD05iMXlDWO-kDHut3uI4MgIEAQ9StK0qOST7fiA=s800-c-k-c0x00ffffff-no-rj",
        fingerprint: "a9377b9b964f7ebbd88f72931699913f")
      subscription!(id: 802, feed: feed, created_at: Time.utc(2023, 11, 2, 19, 47, 15), show_updates: false)
      entry = entry!(
        id: 2948530, feed: feed, title: "The Foldable I Would Actually Buy", author: "Marques Brownlee",
        summary: "Two weeks with the new foldables, and the one hinge that finally changed my mind.",
        url: "https://www.youtube.com/watch?v=#{VIDEO_ID}",
        content: %(<iframe src="https://www.youtube.com/embed/#{VIDEO_ID}" allowfullscreen></iframe>\n<p>Two weeks with the new foldables, and the one hinge that finally changed my mind.</p>),
        published: Time.utc(2026, 9, 7, 16, 0, 12), created_at: Time.utc(2026, 9, 7, 16, 1, 40),
        provider: :youtube, provider_id: VIDEO_ID, provider_parent_id: CHANNEL_ID,
        data: {"youtube_video_id" => VIDEO_ID}
      )
      image!(:entry_preview, entry.id, feed: feed, kind: :poster, path: "37e/37ecad82495f0091a1def4e62252e266.jpg",
        width: 542, height: 304, bytes: 44730, color: "2e3440",
        url: "https://i.ytimg.com/vi/#{VIDEO_ID}/maxresdefault.jpg", fingerprint: "881d329c30e04917dc0065bda56de7a7")
      Embed.create!(source: :youtube_video, provider_id: VIDEO_ID, parent_id: CHANNEL_ID, data: {
        "snippet" => {
          "title" => "The Foldable I Would Actually Buy",
          "channelId" => CHANNEL_ID,
          "liveBroadcastContent" => "none",
          "description" => "0:00 Intro\n1:14 The hinge\n8:06 Battery\n13:07 Which one I'd buy",
          "thumbnails" => {"maxres" => {"url" => "https://i.ytimg.com/vi/#{VIDEO_ID}/maxresdefault.jpg", "width" => 1280, "height" => 720}}
        },
        "contentDetails" => {"duration" => "PT18M47S"}
      })
      Embed.create!(source: :youtube_channel, provider_id: CHANNEL_ID, data: {"snippet" => {"title" => "Marques Brownlee"}})
    end

    def platformer
      feed = feed!(
        id: 3877, title: "Platformer", feed_url: "http://platformer.news?a865afcd81bae336371f2f5a4da28b2f0598d00d",
        site_url: "http://platformer.news", host: "platformer.news", feed_type: :newsletter,
        last_published_entry: Time.utc(2026, 9, 8, 12, 2, 51)
      )
      site_icons(feed,
        favicon: {path: "be0/be0c6d0f69bf01c0917d06e20131c921.png", bytes: 1377, color: "1a1a2e", url: "https://www.platformer.news/favicon.png", fingerprint: "a840a97e74c7a916e19644c792a6299d"})
      subscription!(id: 845, feed: feed, created_at: Time.utc(2024, 5, 20, 8, 15, 33), show_updates: true)
      entry = entry!(
        id: 2949117, feed: feed, title: "The week the App Store blinked", author: nil,
        summary: "Three rule changes in five days, and what they say about who is actually setting policy now.",
        url: "https://www.platformer.news/app-store-blinks/",
        content: %(<p>Three rule changes in five days, and what they say about who is actually setting policy now.</p>\n<p><a href="https://www.platformer.news/app-store-blinks/">View in browser</a></p>),
        published: Time.utc(2026, 9, 8, 12, 2, 51), created_at: Time.utc(2026, 9, 8, 12, 2, 58),
        settings: {"newsletter_from" => "Casey Newton <casey@platformer.news>"}
      )
      image!(:entry_preview, entry.id, feed: feed, kind: :poster, path: "863/863e887326bf3ff582983276e9732bab.jpg",
        width: 542, height: 304, bytes: 52118, color: "3a2f4d",
        url: "https://www.platformer.news/content/images/2026/09/app-store.jpg", fingerprint: "cddac1ceaaeb8cb98818fb1d58eaba74")
    end

    def marco
      feed = feed!(
        id: 4102, title: "Marco Arment", feed_url: "https://mastodon.social/@marcoarment.rss",
        site_url: "https://mastodon.social/@marcoarment", host: "mastodon.social",
        options: {
          "description" => "Public posts from @marcoarment@mastodon.social",
          "image" => {"url" => "https://files.mastodon.social/accounts/avatars/000/012/345/original/a.jpg", "link" => "https://mastodon.social/@marcoarment", "title" => "Marco Arment"}
        },
        last_published_entry: Time.utc(2026, 9, 6, 15, 12, 8)
      )
      site_icons(feed,
        favicon: {path: "4e3/4e3f3ad7ec3bf81869a6733c0ca440a0.png", bytes: 1012, color: "6364ff", url: "https://mastodon.social/favicon.ico", fingerprint: "6c0d423d698c13e99da9c9d1d8ab9203"},
        touch_icon: {path: "3d9/3d9358e184f0afab85af3a434adc7837.png", bytes: 8930, color: "6364ff", url: "https://mastodon.social/apple-touch-icon.png", fingerprint: "84607b85f433c4fe6e2bb2e7f93d1142"})
      avatar = {kind: :avatar, path: "7c7/7c7f38c6f7eb694275390adf0ab20ea6.png", width: 200, height: 200, bytes: 14877, color: "1c2733",
                url: "https://files.mastodon.social/accounts/avatars/000/012/345/original/a.jpg", fingerprint: "f00e1ebc309efff2c64e6d338563f29d"}
      image!(:feed_icon, feed.id, feed: feed, **avatar)
      subscription!(id: 860, feed: feed, created_at: Time.utc(2022, 11, 14, 2, 30, 9), show_updates: false)
      link = "https://daringfireball.net/2026/09/the_change"
      entry = entry!(
        id: 2948881, feed: feed, title: nil, author: "Marco Arment",
        summary: "This is the best explanation of the change I have read.",
        url: "https://mastodon.social/@marcoarment/113884201947",
        content: %(<p>This is the best explanation of the change I have read. <a href="#{link}">daringfireball.net/2026/09/the_change</a></p>),
        published: Time.utc(2026, 9, 6, 15, 12, 8), created_at: Time.utc(2026, 9, 6, 15, 12, 41),
        data: {
          "urls" => [link],
          "saved_pages" => {link => {"result" => {"title" => "The Change", "author" => "John Gruber", "url" => link, "content" => "<p>The change, explained.</p>"}}}
        }
      )
      image!(:entry_icon, entry.id, feed: feed, **avatar, fingerprint: avatar[:fingerprint])
      image!(:entry_link_preview, entry.id, feed: feed, kind: :poster, path: "030/030f71ee1c2885e3e6c2c7cf968e0f1a.jpg",
        width: 542, height: 304, bytes: 51902, color: "3b2f2a",
        url: "https://daringfireball.net/graphics/2026/09/og-image.png", fingerprint: "02836998d604b00f3432b6584d3c3e4f")
    end

    def pages
      feed = feed!(
        id: 4410, title: "Pages", feed_url: "http://pages.feedbin.com/7648187c6ed60a01d0176a5c55722b888fc8750d",
        site_url: "http://pages.feedbin.com", host: "pages.feedbin.com", feed_type: :pages,
        last_published_entry: Time.utc(2026, 9, 9, 17, 4, 11)
      )
      subscription!(id: 871, feed: feed, created_at: Time.utc(2025, 3, 14, 10, 22, 5), show_updates: false, kind: Subscription.kinds[:generated])
      entry!(
        id: 2951002, feed: feed, title: "A Long Read", author: nil, summary: nil,
        public_id: SavePage.public_id_for(current_user, "https://example.com/long-read"),
        url: "https://example.com/long-read",
        content: "<p>The page as Feedbin extracted it when it was saved.</p>",
        published: Time.utc(2026, 9, 9, 17, 4, 11), created_at: Time.utc(2026, 9, 9, 17, 4, 11)
      )
    end

    # Not subscribed.
    def daring_fireball_articles
      feed = feed!(
        id: 1357, title: "Daring Fireball (Articles)", feed_url: "https://daringfireball.net/feeds/articles",
        site_url: "https://daringfireball.net", host: "daringfireball.net",
        options: {"description" => "Mac and web curmudgeonry/nerdery. By John Gruber."},
        last_published_entry: Time.utc(2026, 9, 6, 14, 12, 40)
      )
      entry!(
        id: 2940771, feed: feed, title: "Annoyance-Free Computing", author: "John Gruber",
        summary: "On the small things that wear you down.", url: "https://daringfireball.net/2026/09/annoyance_free",
        content: "<p>On the small things that wear you down.</p>",
        published: Time.utc(2026, 9, 6, 14, 12, 40), created_at: Time.utc(2026, 9, 6, 14, 13, 2)
      )
      # Daily counts, oldest first. Dated from CURRENT_DATE, which FeedStat uses and the frozen clock doesn't reach.
      {1356 => [3, 4, 2, 0, 5, 3, 4, 3, 2, 6, 3, 4, 2, 3, 5, 4, 3, 2, 4, 3, 5, 2, 3, 4, 6, 3, 2, 4, 3, 5],
       1357 => [0, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1]}.each do |feed_id, counts|
        counts.each_with_index do |count, index|
          next if count.zero?
          ActiveRecord::Base.connection.execute(<<~SQL)
            INSERT INTO feed_stats (feed_id, day, entries_count, created_at, updated_at)
            VALUES (#{feed_id}, CURRENT_DATE - #{counts.size - 1 - index}, #{count}, now(), now())
          SQL
        end
      end
    end

    def tags
      apple = Tag.create!(id: 4, name: "Apple")
      podcasts = Tag.create!(id: 9, name: "Podcasts")
      [1356, 2210, 3021].each { Tagging.create!(user: current_user, feed_id: it, tag: apple) }
      Tagging.create!(user: current_user, feed_id: 2210, tag: podcasts)
    end

    def states
      user = current_user
      Entry.where(feed_id: user.subscriptions.select(:feed_id)).where.not(feed_id: 4410).find_each do |entry|
        UnreadEntry.create_from_owners(user, entry)
      end
      StarredEntry.create!(user: user, entry_id: 2945880, feed_id: 1356, published: Time.utc(2026, 9, 4, 4, 30), created_at: Time.utc(2026, 9, 5, 7, 41, 20))
      RecentlyReadEntry.create!(user: user, entry_id: 2949117, created_at: Time.utc(2026, 9, 8, 18, 30, 4))
      UpdatedEntry.create!(user: user, entry_id: 2945880, feed_id: 1356, published: Time.utc(2026, 9, 4, 4, 30), updated: Time.utc(2026, 9, 4, 6, 2, 44))
    end

    def collections
      user = current_user
      Playlist.create!(id: 2, user: user, title: "Commute", sort_order: :custom, created_at: Time.utc(2025, 1, 10, 8, 44, 19), updated_at: Time.utc(2026, 8, 30, 19, 11, 52))
      QueuedEntry.create!(user: user, entry_id: 2947218, feed_id: 2210, order: 0, progress: 1204, duration: 6412, playlist_id: 2, created_at: Time.utc(2026, 9, 8, 14, 2, 11), updated_at: Time.utc(2026, 9, 8, 14, 2, 11))
      QueuedEntry.create!(user: user, entry_id: 2946102, feed_id: 2210, order: 1, progress: 0, duration: 6135, playlist_id: 2, created_at: Time.utc(2026, 8, 29, 7, 15, 2), updated_at: Time.utc(2026, 8, 29, 7, 15, 2))
      PodcastSubscription.create!(user: user, feed_id: 2210, status: :subscribed, created_at: Time.utc(2021, 6, 18, 11, 30, 2))
      RecentlyPlayedEntry.create!(user: user, entry_id: 2946102, progress: 2210, duration: 6135, created_at: Time.utc(2026, 8, 29, 7, 15, 2))
    end

    # Doorkeeper stores only a hash, so the secret goes in through the generator.
    def token
      application = Doorkeeper::Application.create!(id: 31, name: "Unread", redirect_uri: "", scopes: Api::V3::Scopes::FIRST_PARTY, owner: current_user)
      {61 => ["Reeder on Ben’s Mac", Time.utc(2026, 4, 12, 9, 30, 15), Time.utc(2026, 9, 7, 22, 3, 51), "fbn_v3_docsotherdevicetoken0000000000"],
       88 => ["Unread on Ben’s iPhone", Time.utc(2026, 9, 1, 18, 22, 4), Time.utc(2026, 9, 9, 8, 12, 40), ApiDocs::TOKEN]}.each do |id, (name, created_at, used_at, secret)|
        Api::V3::TokenGenerator.stub(:generate, secret) do
          application.access_tokens.create!(id: id, resource_owner_id: 1, scopes: Api::V3::Scopes::FIRST_PARTY,
            device_name: name, created_at: created_at, last_used_at: used_at)
        end
      end
    end

    def account_extras
      user = current_user
      Action.create!(id: 7, user: user, title: "Star Swift posts", query: "title:swift", tag_ids: [4], feed_ids: [], actions: ["star"], action_type: :standard)
      SavedSearch.create!(id: 12, user: user, name: "Swift, unread", query: "title:swift is:unread", created_at: Time.utc(2026, 3, 2, 9, 11, 40), updated_at: Time.utc(2026, 3, 2, 9, 11, 40))
      Device.create!(id: 5120, user: user, token: "9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a0", device_type: :notifier,
        application: "com.feedbin.app", model: "iPad16,3", operating_system: "iPadOS 27.0", created_at: Time.utc(2026, 6, 14, 20, 5, 31))
      import = Import.new(id: 3310, user: user, complete: true, created_at: Time.utc(2026, 9, 9, 16, 58, 2))
      import.save!(validate: false)
      import.import_items.create!(status: :complete, details: {title: "Daring Fireball", xml_url: "https://daringfireball.net/feeds/main", html_url: "https://daringfireball.net"})
      import.import_items.create!(status: :failed, details: {title: "Old Blog", xml_url: "https://example.com/rss", html_url: "https://example.com"})
    end

    def index
      records = [*Entry.where(feed_id: [1356, 1357, 2210, 3021, 3877, 4102, 4410]), *Feed.where(id: [1356, 1357, 2210, 3021, 3877, 4102])].map do |record|
        Search::BulkRecord.new(action: "index", index: Search.index_name(record.class.table_name), id: record.id, document: record.search_data)
      end
      Search.client do |client|
        client.bulk(records)
        client.refresh
      end
    end

    def feed!(id:, **attributes)
      Feed.insert!({id: id, created_at: Time.utc(2012, 1, 1), updated_at: Time.utc(2026, 9, 9), feed_type: Feed.feed_types[attributes.delete(:feed_type) || :xml]}.merge(attributes))
      Feed.find(id)
    end

    def subscription!(id:, feed:, created_at:, **attributes)
      Subscription.insert!({id: id, user_id: 1, feed_id: feed.id, created_at: created_at, updated_at: created_at, active: true, muted: false, media_only: false}.merge(attributes))
    end

    def entry!(id:, feed:, **attributes)
      provider = attributes.delete(:provider)
      row = {
        id: id, feed_id: feed.id, public_id: "docs-#{id}", entry_id: "docs-#{id}", updated_at: attributes[:created_at],
        revision: 1, provider: provider && Entry.providers[provider]
      }.merge(attributes)
      Entry.insert!(row)
      Entry.find(id)
    end

    def image!(provider, provider_id, feed:, kind:, path:, width:, height:, bytes:, color:, url:, fingerprint:)
      Image.create!(
        provider: provider, provider_id: provider_id.to_s, feed_id: feed&.id, kind: kind, url: url,
        variant: "#{width}x#{height}", image_fingerprint: fingerprint, original_fingerprint: fingerprint,
        storage_path: path, width: width, height: height, bytesize: bytes, placeholder_color: color
      )
    end

    def site_icons(feed, favicon: nil, touch_icon: nil)
      {website_favicon: [favicon, 32], website_touch_icon: [touch_icon, 200]}.each do |provider, (icon, size)|
        next unless icon
        image!(provider, feed.host, feed: nil, kind: :site_icon, path: icon[:path], width: size, height: size,
          bytes: icon[:bytes], color: icon[:color], url: icon[:url], fingerprint: icon[:fingerprint])
      end
    end
  end

  # Fixed sequences, so rows a request creates get the same id every run.
  module Sequences
    module_function

    # Above every example id, below every fixture id (all above 30,000,000).
    WORLD = 20_000_000

    # Without start, each table's next id is one past its highest id.
    def reset(start: nil)
      connection = ActiveRecord::Base.connection
      connection.select_rows(<<~SQL).each do |table, sequence|
        SELECT t.relname, s.relname FROM pg_class s
        JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S' AND a.attname = 'id'
      SQL
        value = start || connection.select_value("SELECT COALESCE(MAX(id), 0) + 1 FROM #{connection.quote_table_name(table)} WHERE id < #{WORLD}")
        connection.execute("SELECT setval(#{connection.quote(sequence)}, #{value}, false)")
      end
    end
  end
end
