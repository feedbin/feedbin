require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "favicon_with_host renders the images row first, looked up by lower-cased host" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      Favicon.create!(host: "example.com", url: "http://example.com/legacy.png")
      row = create_favicon_row("example.com")

      html = favicon_with_host("Example.com")

      assert_includes html, "https://images.example.com/#{row.storage_path}"
      refute_includes html, "favicons.example.com"
    end
  end

  # favicons fallback: remove with the favicons table.
  test "favicon_with_host falls back to the favicons row" do
    Favicon.create!(host: "example.com", url: "http://example.com/legacy.png")

    assert_includes favicon_with_host("example.com"), "https://favicons.example.com/legacy.png"
  end

  test "favicon_with_host renders the placeholder when generated and nothing is stored" do
    html = favicon_with_host("nothing.example.com", generated: true)

    assert_includes html, "favicon-default"
    assert_includes html, %(data-color-hash-seed="nothing.example.com")
  end

  test "favicon_with_record ignores a row with no public url" do
    with_env("UNIFIED_IMAGE_HOST" => nil) do
      row = create_favicon_row("example.com")

      assert_includes favicon_with_record(row, host: "example.com", generated: true), "favicon-default"
    end
  end
end
