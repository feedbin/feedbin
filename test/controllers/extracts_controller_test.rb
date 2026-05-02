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

  test "entry returns the entry's own content when extract is not requested" do
    login_as @user
    entry = @entries.first

    get :entry, params: {id: entry, extract: "false"}, xhr: true

    assert_response :success
    # Content is run through ContentFormatter.format!, so just verify it's non-nil
    refute_nil assigns(:content)
  end

  test "entry rescues MercuryParser exceptions and renders successfully" do
    login_as @user
    MercuryParser.stub :parse, ->(*) { raise "boom" } do
      get :entry, params: {id: @entries.first, extract: "true"}, xhr: true
    end
    assert_response :success
  end

  test "entry rescues ContentFormatter exceptions and sets content to nil" do
    login_as @user
    ContentFormatter.stub :format!, ->(*) { raise "boom" } do
      get :entry, params: {id: @entries.first, extract: "false"}, xhr: true
    end
    assert_nil assigns(:content)
    assert_response :success
  end

  test "modal sets content to nil when MercuryParser raises" do
    login_as @user
    MercuryParser.stub :parse, ->(*) { raise "boom" } do
      get :modal, params: {url: "http://example.com/foo"}, xhr: true
    end
    assert_nil assigns(:content)
    assert_response :success
  end
end
