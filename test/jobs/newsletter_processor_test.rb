require "test_helper"

class NewsletterReceiverTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @user = users(:ben)
    @token = @user.newsletter_authentication_token.token
    @newsletter_text = File.read(support_file("email_text.eml"))
    @newsletter_html = File.read(support_file("email_html.eml"))
  end

  test "creates newsletters with new feed and processor" do
    file_url = "https://bucket.s3.amazonaws.com/path.to.email"
    stub_request_file("email_html.eml", file_url)
    stub_request(:delete, file_url)
      .to_return(status: 204)

    assert_difference "Subscription.count", +1 do
      assert_difference "NewsletterSaver.jobs.size", +1 do
        assert_difference("NewsletterSender.count", 1) do
          assert_difference("Entry.count", 1) do
            NewsletterProcessor.new.perform("#{@token}+misc@example.com", "s3://bucket/path.to.email")
          end
        end
      end
    end
    assert @user.feeds.newsletter.exists?
    assert_requested :delete, file_url
  end

end
