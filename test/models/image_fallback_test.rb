require "test_helper"

class ImageFallbackTest < ActiveSupport::TestCase
  test "add_fallbacks attaches an onerror handler to images with an http canonical src" do
    html = <<~HTML
      <p>
        <img src="/proxy/a" data-canonical-src="https://example.com/a.png">
        <img src="/no-canonical">
        <img src="/proxy/b" data-canonical-src="not-a-url">
      </p>
    HTML
    document = Nokogiri::HTML5.fragment(html)
    fallback = ImageFallback.new(document)
    fallback.stub :fallback_url, "https://archive/a.png" do
      fallback.add_fallbacks
    end

    images = document.css("img")
    assert_includes images[0]["onerror"], "https://archive/a.png"
    assert_nil images[1]["onerror"]
    assert_nil images[2]["onerror"]
  end

  test "fallback_url builds a signed URL via Download.path and Fog::Storage" do
    document = Nokogiri::HTML5.fragment("<p>x</p>")
    fallback = ImageFallback.new(document)

    fake_file = Object.new
    fake_file.define_singleton_method(:url) { |_| "https://signed.example/x" }
    fake_files = Object.new
    fake_files.define_singleton_method(:new) { |key:| fake_file }
    fake_directory = Object.new
    fake_directory.define_singleton_method(:files) { fake_files }
    fake_directories = Object.new
    fake_directories.define_singleton_method(:new) { |key:| fake_directory }
    fake_storage = Object.new
    fake_storage.define_singleton_method(:directories) { fake_directories }

    Download.stub :new, ->(_) { OpenStruct.new(path: "k") } do
      Fog::Storage.stub :new, ->(_) { fake_storage } do
        assert_equal "https://signed.example/x", fallback.fallback_url("https://example.com/a.png")
      end
    end
  end
end
