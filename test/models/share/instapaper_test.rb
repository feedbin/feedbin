require "test_helper"

class Share::InstapaperTest < ActiveSupport::TestCase
  CALLBACK = "http://example.com/supported_sharing_services/instapaper/oauth2_response"

  setup do
    @user = users(:ben)
    @entry = @user.feeds.first.entries.create!(
      content: "<p>x</p>",
      title: "An Article",
      url: "https://example.com/article",
      public_id: SecureRandom.hex
    )
    @klass = @user.supported_sharing_services.create!(service_id: "instapaper", access_token: "tok")
  end

  test "authorize_redirect sends the user to the Instapaper consent page" do
    with_env("INSTAPAPER_KEY" => "the-key", "INSTAPAPER_SECRET" => "the-secret") do
      uri = URI(Share::Instapaper.new.authorize_redirect({}, "state-nonce"))
      query = Rack::Utils.parse_query(uri.query)

      assert_equal "https://www.instapaper.com/oauth2/authorize", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_equal "the-key", query["client_id"]
      assert_equal "code", query["response_type"]
      assert_equal "state-nonce", query["state"]
      assert_equal CALLBACK, query["redirect_uri"]
    end
  end

  test "request_access exchanges the code for the bearer token" do
    token_request = stub_request(:post, "https://www.instapaper.com/oauth2/token")
      .with(body: hash_including(
        "client_id" => "the-key",
        "client_secret" => "the-secret",
        "redirect_uri" => CALLBACK,
        "code" => "abc"
      ))
      .to_return(
        status: 200,
        headers: {content_type: "application/json"},
        body: {token_type: "Bearer", access_token: "new-token", user: {id: 42, username: "reader@example.com"}}.to_json
      )

    with_env("INSTAPAPER_KEY" => "the-key", "INSTAPAPER_SECRET" => "the-secret") do
      assert_equal({access_token: "new-token"}, Share::Instapaper.new.request_access(code: "abc"))
    end

    assert_requested token_request
  end

  test "add saves the article with the bearer token and the entry title" do
    bookmark = stub_bookmark_request(body: {url: "https://example.com/article", title: "An Article"})

    assert_equal 200, share_entry

    assert_requested bookmark
  end

  test "add omits the title when the entry has none" do
    @entry.update_column(:title, nil)
    bookmark = stub_bookmark_request(body: {url: "https://example.com/article"})

    assert_equal 200, share_entry

    assert_requested bookmark
  end

  test "add reports a created bookmark as success" do
    stub_bookmark_request(body: hash_including("url" => "https://example.com/article"), status: 201)

    assert_equal 200, share_entry
  end

  test "add passes failure statuses through so the share flow can react" do
    {400 => 400, 401 => 401, 403 => 403, 429 => 429, 500 => 500}.each do |status, expected|
      stub_bookmark_request(body: hash_including("url" => "https://example.com/article"), status: status)

      assert_equal expected, share_entry, "a #{status} response should come back as #{expected}"
    end
  end

  private

  def stub_bookmark_request(body:, status: 200)
    stub_request(:post, "https://www.instapaper.com/api/2/bookmarks")
      .with(body: body, headers: {"Authorization" => "Bearer tok", "Content-Type" => /\Aapplication\/json/})
      .to_return(status: status, headers: {content_type: "application/json"}, body: {id: 1}.to_json)
  end

  def share_entry
    params = ActiveSupport::HashWithIndifferentAccess.new(entry_id: @entry.id, entry_url: @entry.fully_qualified_url)
    Share::Instapaper.new(@klass).add(params)
  end
end
