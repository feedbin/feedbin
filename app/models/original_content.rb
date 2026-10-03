# The first version of an entry's content, compressed with zstd. The entry's
# current content is the dictionary, so the value is tiny, but only that exact
# content can read it back. The first 4 bytes are a CRC32 of that content, so
# a stale value reads as nil, never as wrong text.
module OriginalContent
  def self.compress(original, base:)
    return nil if original.blank? || base.blank?
    [Zlib.crc32(base)].pack("N") + Zstd.compress(original, level: 3, dict: base)
  end

  def self.decompress(blob, base:)
    return nil if blob.nil? || base.blank?
    return nil unless blob.unpack1("N") == Zlib.crc32(base)
    Zstd.decompress(blob.byteslice(4..), dict: base).force_encoding(Encoding::UTF_8)
  rescue RuntimeError => exception
    ErrorService.notify(
      error_class: "OriginalContent#decompress",
      error_message: "zstd decompress failed",
      parameters: {exception: exception}
    )
    nil
  end
end
