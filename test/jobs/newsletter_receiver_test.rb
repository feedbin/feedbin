require "test_helper"

class NewsletterReceiverTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @user = users(:ben)
    @token = @user.newsletter_authentication_token.token
    @newsletter_text = File.read(support_file("email_text.eml"))
    @newsletter_html = File.read(support_file("email_html.eml"))

    @file_url_html = "https://bucket.s3.amazonaws.com/path.to.html.email"
    stub_request_file("email_html.eml", @file_url_html)
    stub_request(:delete, @file_url_html).to_return(status: 204)

    @file_url_text = "https://bucket.s3.amazonaws.com/path.to.text.email"
    stub_request_file("email_text.eml", @file_url_text)
    stub_request(:delete, @file_url_text).to_return(status: 204)

    @s3_url_html = "s3://bucket/path.to.html.email"
    @s3_url_text = "s3://bucket/path.to.text.email"
  end

  test "creates newsletters with new feed and receiver" do
    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            NewsletterReceiver.new.perform(@token, @s3_url_html)
          end
        end
      end
    end
    assert @user.feeds.newsletter.exists?
  end

  test "creates newsletters with new feed and processor" do
    Sidekiq::Worker.clear_all
    user = users(:ben)
    full_token = "#{@token}+miscexample.com"
    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            assert_difference("AuthenticationToken.count", 1) do
              NewsletterReceiver.new.perform("#{@token}+miscexample.com", @s3_url_html)
            end
          end
        end
      end
    end

    assert user.feeds.newsletter.exists?
    assert AuthenticationToken.find_by_token(full_token).present?
    assert_requested :delete, @file_url_html
  end


  test "doesn't create subscription if unsubscribed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)
    feed = Feed.create!(feed_url: newsletter.feed_url)

    assert_no_difference("Subscription.count") do
      NewsletterReceiver.new.perform(@token, @s3_url_html)
    end
    assert !feed.newsletter_sender.active?, "Sender should not be active."
  end

  test "doesn't create newsletter if deactivated" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)
    @user.newsletter_authentication_token.update(active: false)
    assert_no_difference("Entry.count") do
      NewsletterReceiver.new.perform(@token, @s3_url_html)
    end
  end

  test "creates newsletters with old token" do
    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            NewsletterReceiver.new.perform("subscribe+#{@token}", @s3_url_html)
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
        NewsletterReceiver.new.perform(@token, @s3_url_text)
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
        NewsletterReceiver.new.perform(@token, @s3_url_html)
      end
    end
  end

  test "creates newsletters with existing feed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)

    feed = Feed.create!(feed_url: newsletter.feed_url)
    @user.subscriptions.find_or_create_by(feed: feed)

    assert_difference("Entry.count", 1) do
      NewsletterReceiver.new.perform(@token, @s3_url_text)
    end
  end

  test "Updates Feed" do
    newsletter = EmailNewsletter.new(Mail.from_source(@newsletter_text), @token)
    title = SecureRandom.hex
    assert_difference("Entry.count", 1) do
      NewsletterReceiver.new.perform(@token, @s3_url_html)
    end
    feed = Feed.find_by_title("Ben Ubois")
    assert_equal feed.feed_type, "newsletter"
  end
end
