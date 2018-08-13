require "test_helper"

class MicropostTest < ActiveSupport::TestCase
  setup do
    @data = {
      "id" => "1234",
      "author" => {
        "name" => "Name",
        "url" => "https://example.com",
        "avatar" => "https://micro.blog/name/avatar.jpg",
        "_microblog" => {"username" => "username"},
      },
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

  test "should have micropost properties" do
    micropost = Micropost.new(@data, nil)

    assert_equal(@data["author"]["avatar"], micropost.author_avatar)
    assert_equal(@data["author"]["url"], micropost.author_url)
    assert_equal(@data["author"]["name"], micropost.author_name)
    assert_equal("username", micropost.author_username)
    assert_equal("@username", micropost.author_display_username)
    assert_equal("https://micro.blog/username/1234", micropost.url)
  end
end
