require "test_helper"

class TwitterEmbedPartialTest < ActionView::TestCase
  # A dead Twitter URL comes back from camo as a 404; the default avatar
  # takes its place.
  test "the author avatar falls back to the default avatar" do
    media = OpenStruct.new(
      author_url: "https://twitter.com/alice",
      profile_image_url: TwitterAvatar.path("https://pbs.twimg.com/profile_images/1/a.png"),
      permalink: "https://twitter.com/alice/status/1",
      name: "Alice",
      screen_name: "@alice",
      date: Time.utc(2020, 7, 7),
      content: "<p>hi</p>",
      image_url: nil
    )

    html = render(partial: "embeds/twitter", locals: {media: media})

    assert_includes html, TwitterAvatar.path("https://pbs.twimg.com/profile_images/1/a.png")
    assert_includes html, "onerror"
    assert_includes html, "favicon-profile-default"
  end
end
