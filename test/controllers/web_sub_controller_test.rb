require "test_helper"

class WebSubControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    flush_redis
  end

  test "web_sub subscribe" do
    feed = Feed.first

    challenge = Faker::Internet.slug
    get :verify, params: {
      "id"                => feed.id,
      "signature"         => feed.web_sub_callback_signature,
      "hub.topic"         => feed.self_url,
      "hub.lease_seconds" => 10_000,
      "hub.mode"          => "subscribe",
      "hub.challenge"     => challenge
    }

    assert_response :success
    assert_equal challenge, @response.body
    assert_not_nil feed.reload.push_expiration
  end

  test "web_sub unsubscribe" do
    feed = Feed.first

    challenge = Faker::Internet.slug
    get :verify, params: {
      "id"            => feed.id,
      "signature"     => feed.web_sub_callback_signature,
      "hub.topic"     => feed.self_url,
      "hub.mode"      => "unsubscribe",
      "hub.challenge" => challenge
    }

    assert_response :success
    assert_equal challenge, @response.body
  end


  test "web_sub wrong signature" do
    feed = Feed.first

    challenge = Faker::Internet.slug
    get :verify, params: {
      "id"                => feed.id,
      "signature"         => "",
      "hub.topic"         => feed.self_url,
      "hub.lease_seconds" => 10_000,
      "hub.mode"          => "subscribe",
      "hub.challenge"     => challenge
    }

    assert_response :not_found
  end


  test "web_sub publish" do
    feed = @user.feeds.first
    Feed.reset_counters(feed.id, :subscriptions)
    new_title = SecureRandom.hex
    body = <<-EOD
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{new_title}</title>
      <entry>
        <title>Title</title>
        <link href="https://example.com/url/" />
        <id>https://example.com/url/</id>
        <content type="html">content</content>
      </entry>
    </feed>
    EOD

    signature = OpenSSL::HMAC.hexdigest("sha512", feed.web_sub_secret, body)
    @request.headers["HTTP_X_HUB_SIGNATURE"] = "sha512=#{signature}"

    assert_difference "Entry.count", +1 do
      Sidekiq::Testing.inline! do
        post :publish, params: {id: feed.id, signature: feed.web_sub_callback_signature}, body: body
        assert_response :success
      end
    end

    assert_equal(new_title, feed.reload.title)
  end

  test "web_sub publish youtube" do
    feed = @user.feeds.first
    Feed.reset_counters(feed.id, :subscriptions)

    video_id = "I1qsF0WQy8c"
    body = <<-EOD
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015">
      <title>YouTube video feed</title>
      <entry>
        <yt:videoId>#{video_id}</yt:videoId>
        <title>Title</title>
        <link href="https://example.com/url/" />
        <id>https://example.com/url/</id>
        <content type="html">content</content>
      </entry>
    </feed>
    EOD

    signature = OpenSSL::HMAC.hexdigest("sha512", feed.web_sub_secret, body)
    @request.headers["HTTP_X_HUB_SIGNATURE"] = "sha512=#{signature}"

    assert_difference -> { FeedCrawler::YoutubeReceiver.jobs.count }, +1 do
      post :publish, params: {id: feed.id, signature: feed.web_sub_callback_signature}, body: body
      assert_response :success
    end
    receiver_job = FeedCrawler::YoutubeReceiver.jobs.first.dig("args", 0)
    assert_equal(video_id, HarvestEmbeds.new.dequeue_ids(HarvestEmbeds::SET_NAME).first)
    assert_equal(video_id, receiver_job.dig("entries", 0, "data", "youtube_video_id"))
    refute receiver_job.dig("feed", "title"), "Refuse title from youtube WebSub data because it is bogus"
  end
end
