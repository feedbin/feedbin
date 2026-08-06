require "test_helper"

class Share::ServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    @entry = @user.feeds.first.entries.create!(
      content: "<p>hi</p>",
      title: "Hi",
      url: "https://example.com/p/1",
      public_id: SecureRandom.hex
    )
    @klass = @user.supported_sharing_services.create!(service_id: "instapaper", access_token: "t", access_secret: "s")
  end

  test "an entry with no resolvable url is refused rather than retried" do
    @entry.update_column(:url, nil)
    assert_nil @entry.reload.fully_qualified_url

    stub_request(:post, "https://www.instapaper.com/api/1/bookmarks/add").to_return(status: 400, body: "")

    response = nil
    assert_no_difference -> { ShareRetry.jobs.count } do
      response = Share::Instapaper.new(@klass).share(ActiveSupport::HashWithIndifferentAccess.new(entry_id: @entry.id))
    end

    assert response[:error].present?, "the user should be told why it could not be shared"
    assert_not_requested :post, "https://www.instapaper.com/api/1/bookmarks/add"
  end

  test "a failure that could succeed later is still retried" do
    stub_request(:post, "https://www.instapaper.com/api/1/bookmarks/add").to_return(status: 500, body: "")

    assert_difference -> { ShareRetry.jobs.count }, +1 do
      Share::Instapaper.new(@klass).share(ActiveSupport::HashWithIndifferentAccess.new(entry_id: @entry.id))
    end
  end
end
