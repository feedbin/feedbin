require "test_helper"

class NewslettersControllerTest < ActionController::TestCase
  test "doesn't create subscription if unsubscribed" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_token, "asdf"))
    signature = newsletter.send(:signature)

    Feed.create!(feed_url: newsletter.feed_url)

    assert_no_difference("Subscription.count") do
      post :create, params: newsletter_params(user.newsletter_token, signature)
    end
    assert_response :success
  end

  test "creates newsletters with new feed" do
    user = users(:ben)
    signature = Newsletter.new(newsletter_params("asdf", "asdf")).send(:signature)
    token = "#{user.newsletter_token}+other"

    Sidekiq::Worker.clear_all

    assert_difference "NewsletterSaver.jobs.size", +1 do
      assert_difference("NewsletterSender.count", 1) do
        assert_difference("Entry.count", 1) do
          post :create, params: newsletter_params(token, signature)
        end
      end
    end
    assert_response :success

    feed = user.feeds.newsletter.take
    assert_equal(token, feed.options["newsletter_token"])
  end

  test "puts newsletter in tag" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_token, "asdf"))
    signature = newsletter.send(:signature)
    tag = "Newsletters"
    user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Tag.count", 1) do
      assert_difference("Entry.count", 1) do
        post :create, params: newsletter_params(user.newsletter_token, signature)
      end
    end

    assert_response :success
  end

  test "creates newsletters with existing feed" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_token, "asdf"))
    signature = newsletter.send(:signature)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Entry.count", 1) do
      post :create, params: newsletter_params(user.newsletter_token, signature)
    end
    assert_response :success
  end

  test "doesn't create newsletter with invalid signature" do
    user = users(:ben)
    assert_no_difference("Entry.count") do
      post :create, params: newsletter_params(user.newsletter_token, "fdsa")
    end
    assert_response :success
  end

  test "Updates Feed" do
    user = users(:ben)
    signature = Newsletter.new(newsletter_params("asdf", "asdf")).send(:signature)
    title = SecureRandom.hex
    assert_difference("Entry.count", 1) do
      post :create, params: newsletter_params(user.newsletter_token, signature, title)
    end
    assert_response :success
    feed = Feed.find_by_title(title)
    assert feed.options["email_headers"].present?
    assert_equal feed.feed_type, "newsletter"
  end

end
