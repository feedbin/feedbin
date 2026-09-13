require "test_helper"

module ImageCrawler
  class CacheRemoteFileTest < ActiveSupport::TestCase
    def setup
      @url = "bc5431c75680852f26ff34e4688af32b-icon"
      @image = {
        "original_url" => "https://example.com/avatar.jpg",
        "processed_url" => "https://files.example.com/bc5/bc5431c75680852f26ff34e4688af32b-icon.jpg",
        "width" => 240,
        "height" => 240,
      }
    end

    # The proxy stores no images row, so nothing derives the kind later; the
    # caller is the only place that knows what it is asking to cache.
    test "schedule requires kind and passes it to the pipeline" do
      Sidekiq::Worker.clear_all
      url = "https://example.com/avatar.jpg"

      assert_raises(ArgumentError) { CacheRemoteFile.schedule(url) }

      CacheRemoteFile.schedule(url, kind: ::Image.kinds[:avatar])
      args = Pipeline::Find.jobs.last["args"].first
      assert_equal ::Image.kinds[:avatar], args["kind"]
      assert_equal "icon", args["preset_name"]
      assert_equal ::Image.providers[:remote_file], args["provider"]
    end

    # The row is written by Upload; nothing enters the legacy store any more.
    test "writes no remote file on callback" do
      assert_no_difference "RemoteFile.count" do
        CacheRemoteFile.new.perform(@url, @image.merge("storage_path" => "abc/abc123.png"))
      end
    end

    test "the icon preset is png, unified, content addressed, and keeps its callback" do
      preset = Image.new(preset_name: "icon").preset

      assert_equal 200, preset.width
      assert_equal 200, preset.height
      assert_equal :limit_png, preset.crop
      assert_equal "png", preset.format
      assert preset.unified
      assert preset.content_addressed
      assert_not preset.legacy_store
      assert_equal CacheRemoteFile, preset.job_class
    end
  end
end
