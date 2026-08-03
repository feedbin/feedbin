require "test_helper"
require "zlib"
require "stringio"

# The first integration test in the app. CompressedRequest used to read
# REQUEST_PATH, which Rack::Test does not set, so every ActionDispatch
# request 500'd in the middleware stack before reaching a controller.
class CompressedRequestIntegrationTest < ActionDispatch::IntegrationTest
  test "serves an ordinary request through the middleware stack" do
    get login_url
    assert_response :success
  end

  test "decompresses a gzipped extension upload through the middleware stack" do
    user = users(:ben)
    content = "<html><body>Article content</body></html>"
    body = {
      url: "http://example.com/article",
      title: "Example Article",
      content: content,
      page_token: user.page_token
    }.to_json

    compressed = StringIO.new
    Zlib::GzipWriter.wrap(compressed) { |gz| gz.write(body) }

    Sidekiq::Worker.clear_all
    assert_difference "SavePageFromExtension.jobs.size", +1 do
      post "/extension/v1/pages",
        env: {"rack.input" => StringIO.new(compressed.string)},
        headers: {
          "Content-Type" => "application/json",
          "Content-Encoding" => "gzip",
          "Accept" => "application/json"
        }
    end
    assert_response :success

    _user_id, url, title, path = SavePageFromExtension.jobs.last["args"]
    assert_equal "http://example.com/article", url
    assert_equal "Example Article", title
    assert_equal content, File.read(path)
  end
end
