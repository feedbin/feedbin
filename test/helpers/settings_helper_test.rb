require "test_helper"

class SettingsHelperTest < ActionView::TestCase
  setup do
    @user = users(:ben)
  end

  # The bookmarklet is a javascript: url, so it is percent-encoded by the
  # helper. Reverse exactly that encoding rather than CGI.unescape, which would
  # also turn the string-concatenation "+" into a space.
  def bookmarklet_source
    bookmarklet.gsub("%20", " ").gsub("%22", '"')
  end

  test "the bookmarklet fallback submits a form rather than navigating to a GET url" do
    source = bookmarklet_source

    assert_includes source, 'form.method = "POST"'
    assert_includes source, "form.submit()"
    refute_includes source, "window.location =",
      "GET /pages no longer exists, so the fallback cannot navigate to it"
  end

  test "the bookmarklet fallback carries the page token, which is what authenticates it" do
    source = bookmarklet_source

    assert_includes source, @user.page_token
    assert_includes source, "page_token"
  end
end
