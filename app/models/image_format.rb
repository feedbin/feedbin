# Decides whether we're willing to hand a file to libvips.
#
# libvips picks its loader by sniffing content, not by the extension or by what
# we thought we were downloading. Anything it has no native loader for falls
# through to magickload, which passes the bytes to ImageMagick, which sniffs
# them again and may dispatch to an external delegate. Every image we decode was
# fetched from a URL someone else controls, so without a check up front the
# bytes get to choose the decoder.
#
# Rails 8.1.3.1 (CVE-2026-66066) blocks libvips' unfuzzed loaders outright,
# which also blocks ICO, so config/initializers/vips.rb turns that back on. This
# is what makes that tolerable: magick only ever sees files already shaped like
# an image we support.
class ImageFormat
  Unsupported = Class.new(StandardError)

  # Enough for a HEIF ftyp box, and for an XML prolog to appear before <svg.
  HEADER_SIZE = 1024

  HEIF_BRANDS = %w[heic heix heim heis hevc mif1 msf1 avif avis]

  def self.detect(path)
    header = File.binread(path, HEADER_SIZE)
    header && new(header).format
  rescue SystemCallError
    nil
  end

  def self.allowed?(path)
    !detect(path).nil?
  end

  # Returns the path, so it can wrap the argument at the point of use:
  #   Vips::Image.new_from_file(ImageFormat.checked!(file))
  def self.checked!(path)
    raise Unsupported, "unsupported image format: #{path}" if detect(path).nil?
    path
  end

  def initialize(header)
    @header = header.b
  end

  def format
    return :png  if start_with?("\x89PNG\r\n\x1a\n")
    return :jpeg if start_with?("\xFF\xD8\xFF")
    return :gif  if start_with?("GIF87a", "GIF89a")
    return :bmp  if start_with?("BM")
    return :tiff if start_with?("II*\x00", "MM\x00*")
    return :webp if start_with?("RIFF") && at(8, 4) == "WEBP"
    return :heif if at(4, 4) == "ftyp" && HEIF_BRANDS.include?(at(8, 4))
    return :ico  if ico?
    return :svg  if svg?
    nil
  end

  private

  # Reserved word, type 1 (icon), then a non-empty image directory. The first
  # four bytes on their own are too weak to accept — they're two null-ish ints.
  def ico?
    return false unless start_with?("\x00\x00\x01\x00")
    entries = at(4, 2)
    entries&.bytesize == 2 && entries.unpack1("v") > 0
  end

  # The one non-raster format we accept, because plenty of sites now serve an
  # SVG favicon. Drop it from here if that stops being worth librsvg.
  def svg?
    text = @header.dup.force_encoding(Encoding::UTF_8).scrub("")
    text.match?(/\A\u{FEFF}?\s*<(?:\?xml|!--|!DOCTYPE|svg)/i) && text.match?(/<svg[\s>]/i)
  end

  def start_with?(*prefixes)
    @header.start_with?(*prefixes.map(&:b))
  end

  def at(offset, length)
    @header[offset, length]
  end
end
