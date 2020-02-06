require "test_helper"

class NewslettersControllerTest < ActionController::TestCase
  test "doesn't create subscription if unsubscribed" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_authentication_token.token, "asdf"))
    signature = newsletter.send(:signature)

    feed = Feed.create!(feed_url: newsletter.feed_url)

    assert_no_difference("Subscription.count") do
      post :create, params: newsletter_params(user.newsletter_authentication_token.token, signature)
    end
    assert !feed.newsletter_sender.active?, "Sender should not be active."
    assert_response :success
  end

  test "creates newsletters with new feed" do
    user = users(:ben)
    signature = Newsletter.new(newsletter_params("asdf", "asdf")).send(:signature)
    token = "#{user.newsletter_authentication_token.token}+other"

    Sidekiq::Worker.clear_all

    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            post :create, params: newsletter_params(token, signature)
          end
        end
      end
    end
    assert_response :success

    feed = user.feeds.newsletter.take
  end

  test "puts newsletter in tag" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_authentication_token.token, "asdf"))
    signature = newsletter.send(:signature)
    tag = "Newsletters"
    user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Tag.count", 1) do
      assert_difference("Entry.count", 1) do
        post :create, params: newsletter_params(user.newsletter_authentication_token.token, signature)
      end
    end

    assert_response :success
  end

  test "does not tag newsletter that already is" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_authentication_token.token, "asdf"))
    signature = newsletter.send(:signature)
    tag = "Newsletters"
    user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)
    feed.tag("New Tag", user)

    assert_no_difference("Tag.count") do
      assert_difference("Entry.count", 1) do
        post :create, params: newsletter_params(user.newsletter_authentication_token.token, signature)
      end
    end

    assert_response :success
  end

  test "creates newsletters with existing feed" do
    user = users(:ben)
    newsletter = Newsletter.new(newsletter_params(user.newsletter_authentication_token.token, "asdf"))
    signature = newsletter.send(:signature)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Entry.count", 1) do
      post :create, params: newsletter_params(user.newsletter_authentication_token.token, signature)
    end
    assert_response :success
  end

  test "doesn't create newsletter with invalid signature" do
    user = users(:ben)
    assert_no_difference("Entry.count") do
      post :create, params: newsletter_params(user.newsletter_authentication_token.token, "fdsa")
    end
    assert_response :success
  end

  test "Updates Feed" do
    user = users(:ben)
    signature = Newsletter.new(newsletter_params("asdf", "asdf")).send(:signature)
    title = SecureRandom.hex
    assert_difference("Entry.count", 1) do
      post :create, params: newsletter_params(user.newsletter_authentication_token.token, signature, title)
    end
    assert_response :success
    feed = Feed.find_by_title(title)
    assert_equal feed.feed_type, "newsletter"
  end

end
