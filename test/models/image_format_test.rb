require "test_helper"

class ImageFormatTest < ActiveSupport::TestCase
  def write(bytes)
    path = File.join(Dir.tmpdir, "image_format_#{SecureRandom.hex}")
    File.binwrite(path, bytes)
    @paths ||= []
    @paths << path
    path
  end

  teardown do
    @paths&.each { File.unlink(it) rescue Errno::ENOENT }
  end

  test "detects the formats we decode" do
    assert_equal :ico, ImageFormat.detect(support_file("favicon.ico"))
    assert_equal :png, ImageFormat.detect(support_file("image.png"))
    assert_equal :jpeg, ImageFormat.detect(support_file("image.jpeg"))
    assert_equal :gif, ImageFormat.detect(write("GIF89a\x01\x00\x01\x00"))
    assert_equal :bmp, ImageFormat.detect(write("BM\x36\x00\x00\x00"))
    assert_equal :tiff, ImageFormat.detect(write("II*\x00\x08\x00\x00\x00"))
    assert_equal :webp, ImageFormat.detect(write("RIFF\x24\x00\x00\x00WEBPVP8 "))
    assert_equal :heif, ImageFormat.detect(write("\x00\x00\x00\x18ftypavif\x00\x00\x00\x00"))
    assert_equal :svg, ImageFormat.detect(write(%(<svg xmlns="http://www.w3.org/2000/svg"/>)))
    assert_equal :svg, ImageFormat.detect(write(%(<?xml version="1.0"?>\n<!-- hi -->\n<svg width="7"/>)))
  end

  test "rejects content that would reach a delegate" do
    # The whole point: PostScript reaches Ghostscript through magickload.
    assert_nil ImageFormat.detect(write("%!PS-Adobe-3.0\n/Times findfont"))
    assert_nil ImageFormat.detect(write("%PDF-1.4\n1 0 obj"))
    assert_nil ImageFormat.detect(write("push graphic-context\nviewbox 0 0 1 1\n")) # MVG
    assert_nil ImageFormat.detect(write("<?xml version=\"1.0\"?><image><read filename=\"/etc/passwd\"/></image>")) # MSL
  end

  test "rejects junk, truncated and empty files" do
    assert_nil ImageFormat.detect(write(""))
    assert_nil ImageFormat.detect(write("\x00\x00\x01\x00\x00\x00")) # ICO magic, zero entries
    assert_nil ImageFormat.detect(write("\x00\x00\x01")) # too short for the directory count
    assert_nil ImageFormat.detect(write(SecureRandom.bytes(64)))
    assert_nil ImageFormat.detect(write("RIFF\x24\x00\x00\x00AVI LIST")) # RIFF, but not WEBP
    assert_nil ImageFormat.detect("/nonexistent/#{SecureRandom.hex}")
  end

  test "allowed? and checked!" do
    assert ImageFormat.allowed?(support_file("favicon.ico"))
    assert_not ImageFormat.allowed?(write("%!PS-Adobe-3.0"))

    path = support_file("image.png")
    assert_equal path, ImageFormat.checked!(path)
    assert_raises ImageFormat::Unsupported do
      ImageFormat.checked!(write("%!PS-Adobe-3.0"))
    end
  end
end
