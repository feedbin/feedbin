require "test_helper"

class NewslettersControllerTest < ActionController::TestCase
  setup do
    file_url = "https://bucket.s3.amazonaws.com/path.to.email"
    stub_request_file("email_html.eml", file_url)
    stub_request(:delete, file_url)
      .to_return(status: 204)
    stub_request(:get, /benubois\.com/)
      .to_return(status: 200, body: "", headers: {})

    stub_request(:put, /s3\.amazonaws\.com/)
      .to_return(status: 200, body: "", headers: {})

    @newsletter_html = Mail.from_source(File.read(support_file("email_html.eml")))
  end

  test "creates newsletters with new feed" do
    authorize
    user = users(:ben)
    token = "#{user.newsletter_authentication_token.token}+other"

    Sidekiq::Worker.clear_all

    Sidekiq::Testing.inline! do
      assert_difference "Subscription.count", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            post :create, params: newsletter_params(token, nil)
          end
        end
      end
    end
    assert_response :success

    feed = user.feeds.newsletter.take
  end

  test "doesn't create subscription if unsubscribed" do
    authorize
    user = users(:ben)

    feed = Feed.create!(feed_url: "http://benubois.com?06da10b1b9db1b0fd5aa1fdc85777b0bcf6cc2e7")

    Sidekiq::Testing.inline! do
      assert_no_difference("Subscription.count") do
        post :create, params: newsletter_params(user.newsletter_authentication_token.token, nil)
      end
    end

    assert_response :success
  end

  test "puts newsletter in tag" do
    authorize
    user = users(:ben)
    tag = "Newsletters"
    user.update(newsletter_tag: tag)

    Sidekiq::Testing.inline! do
      assert_difference("Tag.count", 1) do
        assert_difference("Entry.count", 1) do
          post :create, params: newsletter_params(user.newsletter_authentication_token.token, nil)
        end
      end
    end

    assert_response :success
  end

  test "does not tag newsletter that already is" do
    authorize
    user = users(:ben)
    newsletter = EmailNewsletter.new(@newsletter_html, user.newsletter_authentication_token.token)
    tag = "Newsletters"
    user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)
    feed.tag("New Tag", user)

    Sidekiq::Testing.inline! do
      assert_no_difference("Tag.count") do
        assert_difference("Entry.count", 1) do
          post :create, params: newsletter_params(user.newsletter_authentication_token.token, nil)
        end
      end
    end

    assert_response :success
  end

  test "creates newsletters with existing feed" do
    authorize
    user = users(:ben)
    newsletter = EmailNewsletter.new(@newsletter_html, user.newsletter_authentication_token.token)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)

    Sidekiq::Testing.inline! do
      assert_difference("Entry.count", 1) do
        post :create, params: newsletter_params(user.newsletter_authentication_token.token, nil)
      end
    end
    assert_response :success
  end

  private

  def authorize
    @request.headers[:authorization] = ActionController::HttpAuthentication::Basic.encode_credentials("newsletters", ENV["NEWSLETTER_PASSWORD"])
  end
end
