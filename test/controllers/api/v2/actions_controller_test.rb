require 'test_helper'

class Api::V2::ActionsControllerTest < ApiControllerTestCase

  setup do
    @user = users(:ben)
    @actions = [actions(:api)]
  end

  test "should get index" do
    login_as @user

    get :index, format: :json
    assert_response :success
    results = parse_json

    keys = %w[title action_type query feed_ids tag_ids actions]
    results.each do |result|
      assert_has_keys(keys, result)
    end
  end

end
