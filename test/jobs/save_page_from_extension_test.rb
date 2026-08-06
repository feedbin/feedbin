require "test_helper"

class SavePageFromExtensionTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
    @user = users(:ben)
    @url = "http://example.com/extension_page"
  end

  # The controller writes the captured DOM to tmpdir under a random name and
  # this worker is the only thing that knows it is there. Nothing else sweeps
  # it, and the file holds whatever page the user was signed in to.
  test "removes the file the extension captured" do
    stub_request_file("parsed_page.json", /extract\.example\.com/, {headers: {"Content-Type" => "application/json; charset=utf-8"}}, :post)

    SavePageFromExtension.new.perform(@user.id, @url, "Title", captured_page)

    assert_not File.exist?(captured_page), "the captured page should not be left on disk"
  end

  # `retry: false`, so an unparseable capture is not coming back for another
  # run — raising MissingPage here could only land in the error tracker. Hand
  # the retry to the worker that has one: a url crawl needs no captured file.
  test "falls back to a url crawl when the captured page cannot be parsed" do
    stub_request(:post, /extract\.example\.com/).to_return(status: 500)

    assert_nothing_raised do
      assert_difference "SavePage.jobs.size", +1 do
        SavePageFromExtension.new.perform(@user.id, @url, "Title", captured_page)
      end
    end

    assert_equal [@user.id, @url, "Title"], SavePage.jobs.last["args"]
    assert_not File.exist?(captured_page), "the captured page should not be left on disk"
  end

  private

  def captured_page
    @captured_page ||= File.join(Dir.tmpdir, "pages_#{SecureRandom.hex}.html").tap do |path|
      File.write(path, "<html><body><p>whatever the user was reading</p></body></html>")
    end
  end
end
