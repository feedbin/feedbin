require 'test_helper'

class TagsControllerTest < ActionController::TestCase

  def setup
    @user = users(:ben)
    @tag = @user.feeds.first.tag('Tag', @user).first.tag
  end

  test "should get index" do
    login_as @user
    get :index, query: @tag.name, format: :json
    assert_response :success
    data = JSON.parse(@response.body)
    assert_kind_of Array, data['suggestions']
    ['value', 'data'].each do |key|
      assert data['suggestions'].first.key?(key)
    end
  end

  test "should show tag" do
    login_as @user
    xhr :get, :show, id: @tag
    assert_response :success
  end

  test "should update tag" do
    login_as @user
    assert_difference "Tag.count", +1 do
      xhr :post, :update, id: @tag, tag: {name: "#{@tag.name} New"}
      assert_response :success
    end
  end

  test "should destroy tag" do
    login_as @user
    assert_difference "Tagging.count", -1 do
      xhr :delete, :destroy, id: @tag
      assert_response :success
    end
  end

end
