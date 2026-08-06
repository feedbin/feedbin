require "test_helper"

class Api::V2::ActionsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @entry = @entries.first
    action = Action.create(
      user: @user,
      query: @entry.title,
      feed_ids: @feeds.map(&:id),
      actions: ["mark_read"]
    )
    @actions = [action]
  end

  test "should get index" do
    login_as @user

    get :index, format: :json
    assert_response :success
    results = parse_json

    results.each do |result|
      assert_has_keys(action_keys, result)
    end
  end

  test "should create action" do
    api_content_type
    login_as @user
    assert_difference "Action.count", +1 do
      post :create, format: :json, params: {
        action_params: {
          query: "query",
          feed_ids: [@feeds.first.id],
          actions: ["mark_read"]
        }
      }
      assert_response :success
    end
  end

  test "should update action" do
    api_content_type
    login_as @user
    action = @actions.first
    query = "#{action.query} new"
    patch :update, params: {id: action, action_params: {query: query}}, format: :json
    assert_response :success
    assert_equal query, action.reload.query
  end

  test "should get results" do
    login_as @user
    get :results, params: {id: @actions.first}, format: :json
    assert_includes assigns(:entries).to_a, @entry
  end

  # The endpoint returns 200 with a plausible list either way, so asserting on
  # what reaches the search is the only thing that catches an unconstrained one.
  test "results searches on the action's own criteria" do
    login_as @user
    action = @actions.first
    captured = nil

    Entry.stub(:scoped_search, ->(query, _user) { captured = query; Search::Response.new({}) }) do
      get :results, params: {id: action.id}, format: :json
    end

    assert_equal action.query, captured[:query]
    assert_equal action.computed_feed_ids, captured[:feed_ids]
  end

  test "results_watch restricts the search to unread entries" do
    login_as @user
    @actions.first.update!(action_type: Action.action_types[:notifier])
    captured = nil

    Entry.stub(:scoped_search, ->(query, _user) { captured = query; Search::Response.new({}) }) do
      get :results_watch, format: :json
    end

    assert_equal false, captured[:read]
    assert_equal @actions.first.query, captured[:query]
  end

  private

  def action_keys
    %w[title action_type query feed_ids tag_ids actions]
  end
end
