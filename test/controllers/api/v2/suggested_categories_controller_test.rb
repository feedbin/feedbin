require "test_helper"

class Api::V2::SuggestedCategoriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @category = SuggestedCategory.create!(id: 1, name: "Popular")
  end

  test "gets index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    results = parse_json

    assert_has_keys keys, results.first
  end

  private

  def keys
    %w[icon_url id name]
  end
end
