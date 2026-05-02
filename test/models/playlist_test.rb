require "test_helper"

class PlaylistTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "defaults to the custom sort_order" do
    playlist = @user.playlists.create!(title: "Mine")
    assert_predicate playlist, :custom?
  end

  test "supports newest_first and oldest_first sort orders" do
    playlist = @user.playlists.create!(title: "Mine", sort_order: :newest_first)
    assert_predicate playlist, :newest_first?

    playlist.update!(sort_order: :oldest_first)
    assert_predicate playlist, :oldest_first?
  end

  test "tracking title creates an AttributeChange when title changes" do
    playlist = @user.playlists.create!(title: "Original")

    assert_difference -> { playlist.attribute_changes.where(name: "title").count }, +1 do
      playlist.update!(title: "Renamed")
    end
  end

  test "tracking sort_order creates an AttributeChange when sort_order changes" do
    playlist = @user.playlists.create!(title: "Mine")

    assert_difference -> { playlist.attribute_changes.where(name: "sort_order").count }, +1 do
      playlist.update!(sort_order: :newest_first)
    end
  end
end
