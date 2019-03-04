require "test_helper"

class ExtractsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end

  test "should extract content" do
    login_as @user
    content = Faker::Lorem.paragraph
    struct = OpenStruct.new(content: content)
    MercuryParser.stub :parse, struct do
      get :entry, params: {id: @entries.first, extract: "true"}, xhr: true
    end
    assert_equal assigns(:content), content
    assert_response :success
  end

  test "should extract content modal" do
    login_as @user
    content = Faker::Lorem.paragraph
    struct = OpenStruct.new(content: content)
    MercuryParser.stub :parse, struct do
      get :modal, params: {id: @entries.first, extract: "true"}, xhr: true
    end
    assert_equal assigns(:content), content
    assert_response :success
  end

  test "should prefire extract" do
    login_as @user
    Sidekiq::Worker.clear_all
    assert_difference "ViewLinkCache.jobs.size", +1 do
      get :cache, params: {url: "url"}, xhr: true
    end
  end

end
