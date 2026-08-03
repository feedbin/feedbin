require "test_helper"

# The auto_sign_in route is wrapped in a development-only routing constraint, so
# the guard is exercised directly. It is load-bearing documentation: the comment
# above it promises relative paths only.
class SiteControllerDestinationTest < ActiveSupport::TestCase
  ROOT = "http://test.host/"

  def destination_for(path)
    controller = SiteController.new
    controller.params = ActionController::Parameters.new(path: path)
    # A bare controller has no request, so it cannot build root_url itself.
    controller.define_singleton_method(:root_url) { ROOT }
    controller.send(:destination)
  end

  test "refuses a protocol-relative url" do
    assert_equal ROOT, destination_for("//evil.example.com/")
    assert_equal ROOT, destination_for("//evil.example.com")
  end

  test "refuses a backslash-smuggled host" do
    assert_equal ROOT, destination_for("/\\evil.example.com")
  end

  test "refuses an absolute url" do
    assert_equal ROOT, destination_for("https://evil.example.com")
    assert_equal ROOT, destination_for("javascript:alert(1)")
  end

  test "refuses a path that does not start with a slash" do
    assert_equal ROOT, destination_for("settings")
    assert_equal ROOT, destination_for("")
  end

  test "keeps ordinary relative paths" do
    assert_equal "/settings", destination_for("/settings")
    assert_equal "/settings/billing", destination_for("/settings/billing")
    assert_equal "/entries/1?foo=bar", destination_for("/entries/1?foo=bar")
  end
end
