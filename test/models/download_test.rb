require "test_helper"

class DownloadTest < ActiveSupport::TestCase
  # `src` reaches here verbatim out of entry content, filtered only by
  # start_with?("http"), so it is whatever a CMS published.
  test "builds a path for src values RFC 3986 rejects but browsers accept" do
    {
      "http://example.com/a b.png" => ".png",
      "http:logo.png" => ".png",
      "http://example.com/x.png?cache=1" => ".png",
      "http://example.com/no-extension" => ""
    }.each do |url, extension|
      path = Download.new(url).path

      assert path.end_with?(extension), "#{url} should keep its #{extension.presence || "empty"} extension"
    end
  end

  # A feed update fans out one ImageSaver per entry, and a syndicated image, a
  # site logo or a tracking pixel appears in many entries at once. Those jobs
  # share Dir.tmpdir, and `download` opens the file "wb" while `delete`
  # unlinks it, so a shared path means one job truncates or removes the file
  # another is uploading.
  test "two downloads of the same url do not share a temp file in the shared tmpdir" do
    url = "https://example.com/logo.png"

    refute_equal Download.new(url).file_path.to_s, Download.new(url).file_path.to_s
  end

  # MakeEpub hands Download the epub's own images directory and then links to
  # the file by `filename` from the article markup, so a caller that names the
  # directory owns it and must get the file under exactly that name.
  test "a caller-supplied directory holds the file under its deterministic filename" do
    download = Download.new("https://example.com/logo.png", "/epub/images")

    assert_equal "/epub/images/#{download.filename}", download.file_path.to_s
  end
end
