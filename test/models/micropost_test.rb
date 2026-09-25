require "test_helper"

class MicropostTest < ActiveSupport::TestCase
  setup do
    @data = {
      "id" => "1234",
      "author" => {
        "name" => "Name",
        "url" => "https://example.com",
        "avatar" => "https://micro.blog/name/avatar.jpg",
        "_microblog" => {"username" => "username"}
      }
    }
  end

  test "should be a micropost" do
    micropost = Micropost.new(@data, nil)
    assert micropost.valid?
  end

  test "should not be a micropost" do
    micropost = Micropost.new(@data, "Title")
    assert_not micropost.valid?
  end

  test "should also not be a micropost" do
    micropost = Micropost.new(nil, "Title")
    assert_not micropost.valid?
  end

  # The pipeline stores the image on a row, not in
  # twitter_link_image_processed; the gate must accept the row too.
  test "link_preview? accepts a stored link image row in place of the legacy data key" do
    data = @data.merge(
      "urls" => ["https://example.com/p"],
      "saved_pages" => {"https://example.com/p" => {"result" => {"ok" => true}}}
    )
    assert Micropost.new(data, nil, link_image: Object.new).link_preview?
  end

  test "should have micropost properties" do
    micropost = Micropost.new(@data, nil)

    assert_equal(@data["author"]["avatar"], micropost.author_avatar)
    assert_equal(@data["author"]["url"], micropost.author_url)
    assert_equal(@data["author"]["name"], micropost.author_name)
    assert_equal("username", micropost.author_username)
    assert_equal("@username", micropost.author_display_username)
    assert_equal("https://micro.blog/username/1234", micropost.url)
  end

  test "link_preview? ignores the legacy data key without a link row" do
    data = @data.merge(
      "urls" => ["https://example.com/p"],
      "saved_pages" => {"https://example.com/p" => {"result" => {"ok" => true}}},
      "twitter_link_image_processed" => "x"
    )
    refute Micropost.new(data, nil).link_preview?
  end
end
