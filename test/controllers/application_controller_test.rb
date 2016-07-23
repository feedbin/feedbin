require 'test_helper'

class ApplicationControllerTest < ActionController::TestCase

  test "should update session" do
    data = {
      "selected_feed_data" => 1,
      "selected_feed_type" => "collection_all",
      "selected_feed" => "collection_all_1"
    }
    @controller.update_selected_feed!(data["selected_feed_type"], data["selected_feed_data"])
    data.each do |key, value|
      assert_equal session[key], value
    end
  end

  test "get collections" do
    login_as users(:ben)
    keys = [:title, :path, :count_data, :id, :favicon_class, :parent_class, :parent_data, :data]
    collections = @controller.get_collections
    collections.each do |collection|
      assert keys.all? { |key| collection.key?(key) }
    end
  end

  test "feeds list" do
    login_as users(:ben)
    @controller.get_feeds_list
    assigns(:mark_selected)
  end

end
