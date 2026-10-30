# Sample data for API v3: one user subscribed to a feed of every entry kind,
# with the data shapes each kind carries (image rows, enclosures and
# chapters, YouTube ids, newsletter senders, micropost authors and saved
# link pages, saved pages, and revised entries with an original).
#
#   rails runner script/api_v3_sample_data.rb [entries per feed, default 200]
#
# Development only. Rerunning replaces the previous sample user and feeds.

abort "Development only." unless Rails.env.development?

PER_FEED = Integer(ARGV[0] || 200)
EMAIL = "api-v3-sample@example.com"
SAMPLE_HOST = "sample.feedbin.test"
random = Random.new(42)

def image_row(entry_or_key, provider:, kind:, variant: "542x304", width: 542, height: 304, bytesize: 48_000)
  url = "https://#{SAMPLE_HOST}/images/#{SecureRandom.hex(8)}.jpg"
  Image.create!(
    provider: provider,
    provider_id: entry_or_key.respond_to?(:id) ? entry_or_key.id.to_s : entry_or_key,
    feed_id: entry_or_key.respond_to?(:feed_id) ? entry_or_key.feed_id : nil,
    kind: kind,
    url: url,
    variant: variant,
    image_fingerprint: SecureRandom.uuid,
    original_fingerprint: SecureRandom.uuid,
    storage_path: Image.storage_path_for(url, variant),
    width: width,
    height: height,
    bytesize: bytesize,
    placeholder_color: SecureRandom.hex(3)
  )
end

# Remove the previous run.
if (old = User.find_by(email: EMAIL))
  feed_ids = old.subscriptions.pluck(:feed_id)
  entry_ids = Entry.where(feed_id: feed_ids).pluck(:id)
  Image.where(provider_id: entry_ids.map(&:to_s)).delete_all
  Image.where(feed_id: feed_ids).delete_all
  Image.where("url LIKE ?", "https://#{SAMPLE_HOST}/%").delete_all
  UnreadEntry.where(user_id: old.id).delete_all
  StarredEntry.where(user_id: old.id).delete_all
  Entry.where(feed_id: feed_ids).delete_all
  old.subscriptions.delete_all
  Feed.where(id: feed_ids).delete_all
  old.oauth_applications.destroy_all
  old.authentication_tokens.delete_all
  old.delete
end

user = User.new(email: EMAIL, password: SecureRandom.hex(16), plan: Plan.find_by!(stripe_id: "trial"))
user.save!(validate: false)
user.setting_on!(:api_v3)
user.setting_off!(:needs_onboarding)

articles = JSON.parse(File.read(Rails.root.join("test/support/www/feed.json")))["items"].map { _1["content_html"] }
show_notes = Entry.where("length(content) > 500").limit(200).pluck(:content)
show_notes = articles if show_notes.empty?

newsletter_block = <<~HTML
  <table width="100%%" cellpadding="0" cellspacing="0" style="font-family:Helvetica,Arial,sans-serif;background:#ffffff;border-bottom:1px solid #e5e5e5">
    <tr><td style="padding:24px 32px"><h2 style="font-size:22px;line-height:28px;color:#111111;margin:0 0 12px">%<title>s</h2>
    <p style="font-size:16px;line-height:24px;color:#333333;margin:0 0 16px">%<body>s</p>
    <a href="https://newsletter.example/click?u=%<id>s" style="color:#0066cc;text-decoration:underline">Read more</a></td></tr>
  </table>
HTML

feeds = {
  article: Feed.create!(feed_url: "https://#{SAMPLE_HOST}/articles.xml", site_url: "https://#{SAMPLE_HOST}", host: SAMPLE_HOST, title: "Sample Articles", feed_type: :xml),
  podcast: Feed.create!(feed_url: "https://#{SAMPLE_HOST}/podcast.xml", site_url: "https://#{SAMPLE_HOST}/podcast", host: SAMPLE_HOST, title: "Sample Podcast", feed_type: :xml),
  video: Feed.create!(feed_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsample#{SecureRandom.hex(4)}", site_url: "https://www.youtube.com", host: "www.youtube.com", title: "Sample Channel", feed_type: :xml),
  newsletter: Feed.create!(feed_url: "https://#{SAMPLE_HOST}/newsletter/#{SecureRandom.hex(4)}", site_url: "https://newsletter.example", host: "newsletter.example", title: "Sample Newsletter", feed_type: :newsletter),
  micropost: Feed.create!(feed_url: "https://mastodon.example/@sample.rss", site_url: "https://mastodon.example/@sample", host: "mastodon.example", title: "Sample Mastodon", feed_type: :xml),
  page: Feed.create!(feed_url: "https://#{SAMPLE_HOST}/pages/#{SecureRandom.hex(4)}", site_url: "https://#{SAMPLE_HOST}", host: SAMPLE_HOST, title: "Pages", feed_type: :pages)
}
feeds.each_value { user.subscriptions.create!(feed: _1) }
image_row(feeds[:podcast].id.to_s, provider: :feed_icon, kind: :cover_art, variant: "200x200", width: 200, height: 200).update!(feed_id: feeds[:podcast].id)
channels = 3.times.map { "UC#{SecureRandom.alphanumeric(22)}" }
channels.each { image_row(_1, provider: :embed_icon, kind: :avatar, variant: "200x200", width: 200, height: 200) }

PER_FEED.times do |index|
  received = (PER_FEED - index).hours.ago
  base = {public_id: SecureRandom.hex, entry_id: SecureRandom.hex, created_at: received, published: received - random.rand(3600).seconds}

  article = feeds[:article].entries.create!(base.merge(
    title: "Sample article #{index}: #{%w[Filesystems Timelines Caching Fonts Gzip].sample(random: random)}",
    author: "Sample Author",
    url: "https://#{SAMPLE_HOST}/articles/#{index}",
    content: index.even? ? articles.sample(random: random) : show_notes.sample(random: random),
    categories: %w[Technology Apple Design].sample(random.rand(0..2), random: random),
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))
  image_row(article, provider: :entry_preview, kind: :poster) if index % 3 != 0
  if index % 7 == 0
    original = article.content
    revised = original + "<p>Update: #{"this article was revised after publishing. " * 4}</p>"
    article.update_columns(content: revised, compressed_original_content: OriginalContent.compress(original, base: revised), revision: 3, edited_at: received + 2.hours)
  end

  episode = feeds[:podcast].entries.create!(base.merge(
    title: "#{400 + index}: Sample Episode",
    author: "Sample Podcast",
    url: "https://#{SAMPLE_HOST}/podcast/#{400 + index}",
    content: show_notes.sample(random: random),
    data: {"enclosure_url" => "https://cdn.#{SAMPLE_HOST}/episodes/#{400 + index}.mp3", "enclosure_type" => "audio/mpeg", "enclosure_length" => (40_000_000 + random.rand(20_000_000)).to_s, "itunes_duration" => "1:#{random.rand(10..59)}:#{random.rand(10..59)}"},
    chapters: (index.even? ? 18.times.map { {"start_time" => (_1 * 312.25).to_s, "tags" => {"title" => "Chapter #{_1 + 1}: #{%w[Follow-up Filesystems Sponsor Timelines After\ show].sample(random: random)}"}} } : nil),
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))
  image_row(episode, provider: :entry_icon, kind: :cover_art, variant: "200x200", width: 200, height: 200) if index % 2 == 0

  video_id = SecureRandom.alphanumeric(11)
  channel = channels[index % channels.size]
  video = feeds[:video].entries.create!(base.merge(
    title: "Sample video #{index}",
    author: "Sample Channel",
    url: "https://www.youtube.com/watch?v=#{video_id}",
    content: "Video description #{index}. " * 20,
    data: {"youtube_video_id" => video_id, "youtube_channel_id" => channel},
    provider: :youtube, provider_id: video_id, provider_parent_id: channel,
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))
  image_row(video, provider: :entry_preview, kind: :poster, variant: "542x304")

  feeds[:newsletter].entries.create!(base.merge(
    title: "Sample newsletter issue #{index}",
    author: "Sample Newsletter",
    url: "https://newsletter.example/issues/#{index}",
    content: 25.times.map { format(newsletter_block, title: "Story #{_1}", body: "A paragraph about story #{_1}. " * 6, id: SecureRandom.hex(6)) }.join,
    settings: {"newsletter_from" => %("Sample Newsletter" <hello@newsletter.example>)},
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))

  link = "https://#{SAMPLE_HOST}/linked/#{index}"
  linked_article = articles.sample(random: random)
  post = feeds[:micropost].entries.create!(base.merge(
    title: nil,
    author: "Sample Person",
    url: "https://mastodon.example/@sample/#{100_000 + index}",
    content: %(<p>Worth reading: <a href="#{link}">#{link}</a> #{"so good " * random.rand(1..8)}</p>),
    data: {
      "json_feed" => {"author" => {"name" => "Sample Person", "url" => "https://mastodon.example/@sample", "avatar" => "https://mastodon.example/avatar.png"}, "authors" => [{"name" => "Sample Person", "_social" => {"username" => "sample@mastodon.example"}}]},
      "urls" => [link],
      "saved_pages" => {link => {"result" => {"title" => "Linked article #{index}", "author" => "Linked Author", "url" => link, "domain" => SAMPLE_HOST, "content" => linked_article, "word_count" => 1000}, "url" => link}}
    },
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))
  image_row(post, provider: :entry_icon, kind: :avatar, variant: "200x200", width: 200, height: 200)
  image_row(post, provider: :entry_link_preview, kind: :poster)

  feeds[:page].entries.create!(base.merge(
    title: "Saved page #{index}",
    author: "Page Author",
    url: "https://saved.example/#{index}",
    content: articles.sample(random: random),
    public_id: SecureRandom.hex, entry_id: SecureRandom.hex
  ))
end

# Creating an entry marks it unread for subscribers, so everything starts
# unread.
entries = Entry.where(feed_id: feeds.values.map(&:id))

application = user.oauth_applications.create!(name: "Sample", redirect_uri: "")
token = application.access_tokens.create!(resource_owner_id: user.id, scopes: "full", device_name: "Profiling")
puts "user #{user.id} (#{EMAIL}), #{entries.count} entries across #{feeds.size} feeds"
puts "token #{token.plaintext_token}"
