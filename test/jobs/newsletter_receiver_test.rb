require "test_helper"

class NewsletterReceiverTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @user = users(:ben)
    @token = @user.newsletter_authentication_token.token
    @newsletter_text = File.read(support_file("email_text.eml"))
    @newsletter_html = File.read(support_file("email_html.eml"))
  end

  test "doesn't create subscription if unsubscribed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)
    feed = Feed.create!(feed_url: newsletter.feed_url)

    assert_no_difference("Subscription.count") do
      NewsletterReceiver.new.perform(@token, @newsletter_html)
    end
    assert !feed.newsletter_sender.active?, "Sender should not be active."
  end

  test "creates newsletters with new feed" do
    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            NewsletterReceiver.new.perform(@token, @newsletter_html)
          end
        end
      end
    end
    assert @user.feeds.newsletter.exists?
  end

  test "creates newsletters with old token" do
    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            NewsletterReceiver.new.perform("subscribe+#{@token}", @newsletter_html)
          end
        end
      end
    end
    assert @user.feeds.newsletter.exists?
  end

  test "puts newsletter in tag" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)

    tag = "Newsletters"
    @user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    @user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Tag.count", 1) do
      assert_difference("Entry.count", 1) do
        NewsletterReceiver.new.perform(@token, @newsletter_html)
      end
    end
  end

  test "does not tag newsletter that already is" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)

    tag = "Newsletters"
    @user.update(newsletter_tag: tag)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    @user.subscriptions.find_or_create_by(feed: feed)
    feed.tag("New Tag", @user)

    assert_no_difference("Tag.count") do
      assert_difference("Entry.count", 1) do
        NewsletterReceiver.new.perform(@token, @newsletter_html)
      end
    end
  end

  test "creates newsletters with existing feed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    @user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Entry.count", 1) do
      NewsletterReceiver.new.perform(@token, @newsletter_html)
    end
  end

  test "Updates Feed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)
    title = SecureRandom.hex
    assert_difference("Entry.count", 1) do
      NewsletterReceiver.new.perform(@token, @newsletter_html)
    end
    feed = Feed.find_by_title("Ben Ubois")
    assert_equal feed.feed_type, "newsletter"
  end
end
