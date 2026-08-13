require "test_helper"

class EntryPresenterTest < ActionView::TestCase
  setup do
    @feed = feeds(:daring_fireball)
  end

  def presenter_for(entry)
    EntryPresenter.new(entry, nil, view)
  end

  def entry_with(attributes)
    @feed.entries.create!({
      title: "Episode 1",
      url: "http://example.com/episode-1",
      public_id: SecureRandom.hex,
      entry_id: SecureRandom.hex
    }.merge(attributes))
  end

  # media_image is entry.itunes_image || entry.feed.custom_icon. Distinct
  # values on each side so a regression that returned the show's icon here
  # would visibly fail rather than coincidentally match.
  test "media_image prefers the episode's artwork over the show's" do
    @feed.update!(custom_icon: "https://show.example.com/icon.jpg")
    entry = entry_with(media_image: "https://episode.example.com/cover.jpg")

    assert_equal "https://episode.example.com/cover.jpg", presenter_for(entry).media_image
  end

  test "media_image falls back to the show's artwork when the episode has none" do
    @feed.update!(custom_icon: "https://show.example.com/icon.jpg")
    entry = entry_with({})

    assert_equal "https://show.example.com/icon.jpg", presenter_for(entry).media_image
  end

  test "media_image is nil when neither the episode nor the show has artwork" do
    entry = entry_with({})

    assert_nil presenter_for(entry).media_image
  end
end
