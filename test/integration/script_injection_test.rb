require "test_helper"

# The router's default :id segment is [^/.?]+, so a comma, parentheses and an
# equals sign are all ordinary path characters. HTML escaping does not touch
# them, and inside a <script> element the browser decodes no entities, so ERB's
# default escaping is not an escaping scheme for this context.
class ScriptInjectionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:ben)
    @feed = feeds(:daring_fireball)
    @entry = create_entry(@feed)
    post sessions_url, params: {email: @user.email, password: default_password}
  end

  test "the app page emits a resolved integer id, not the raw path segment" do
    get "/entries/#{@entry.id},alert(1)", headers: {"Accept" => "text/html"}

    call = response.body[/feedbin\.showEntry\([^)]*\)/]
    assert call, "expected the app page to emit the showEntry call"
    assert_equal "feedbin.showEntry(#{@entry.id})", call
    refute_includes response.body, "alert(1)"
  end

  # No "." in the payload: the router takes it as the format separator, which is
  # why the js request 406s rather than reaching the template.
  test "entries#show.js emits a resolved integer id" do
    get "/entries/#{@entry.id});alert(1);x=(",
      headers: {"Accept" => "text/javascript", "X-Requested-With" => "XMLHttpRequest"}

    assert_response :success
    refute_includes response.body, "alert(1)"
    assert_includes response.body, "feedbin.showEntry(#{@entry.id})"
  end

  test "the subscriptions destroy script escapes the stored location" do
    subscription = @user.subscriptions.first
    get "/settings/subscriptions", env: {"QUERY_STRING" => %(q=";feedbin.pwned=1;//)}

    delete "/settings/subscriptions/#{subscription.id}",
      headers: {"X-Requested-With" => "XMLHttpRequest"}

    assert_response :success
    refute_includes response.body, %(";feedbin.pwned=1)
  end
end
