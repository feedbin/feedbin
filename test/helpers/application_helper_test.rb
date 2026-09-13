require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "favicon_with_host renders the images row, looked up by lower-cased host" do
    with_env("UNIFIED_IMAGE_HOST" => "images.example.com") do
      row = create_favicon_row("example.com")

      html = favicon_with_host("Example.com")

      assert_includes html, "https://images.example.com/#{row.storage_path}"
    end
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
