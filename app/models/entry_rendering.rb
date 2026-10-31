# Every formatted version of one entry, stored so a read serves bytes instead
# of running ContentFormatter. The blob is a 5-byte header (layout version,
# CRC32 of the inputs) and one zstd frame compressed with the entry's content
# as its dictionary, so a version costs little beyond what differs from the
# content. A row whose VERSION or CRC does not match its entry is stale and
# is rendered again (Entry#rendering).
class EntryRendering < ApplicationRecord
  self.primary_key = :entry_id

  belongs_to :entry, inverse_of: :rendering_record

  LAYOUT = 1
  VERSIONS = %i[web api full diff].freeze
  # Each version is a 4-byte length and its bytes, in VERSIONS order.
  PACKING = "Na*" * VERSIONS.size

  # The HTML an entry's web and api versions are formatted from. Text entries
  # are paragraphed first, and a YouTube entry gets its player ahead of the
  # description.
  def self.source_html(entry, html = entry.content)
    if entry.content_format == "text"
      ContentFormatter.text_email(html).to_s
    elsif entry.data && entry.data["youtube_video_id"].present?
      player = ActionController::Base.helpers.content_tag(:iframe, "", src: "https://www.youtube.com/embed/#{entry.data["youtube_video_id"]}?rel=0&amp;showinfo=0", frameborder: 0, allowfullscreen: true, width: 1280, height: 720)
      player.to_str + ContentFormatter.text_email(html).to_s
    else
      html.to_s
    end
  end

  def self.versions_for(entry)
    source = source_html(entry)
    web = ContentFormatter.render(:web, source, entry: entry)
    {
      web: web,
      api: ContentFormatter.render(:api, source, entry: entry),
      full: (ContentFormatter.render(:full, source, entry: entry) if entry.feed&.newsletter?),
      diff: diff_for(entry, web)
    }
  end

  # Only for an entry whose first version was kept and differs in length,
  # the rule the diff view has always used. A failed diff is no diff.
  def self.diff_for(entry, web)
    content = entry.content
    original = entry.original_content
    return nil unless content && original.present? && original.length != content.length
    before = ContentFormatter.render(:web, source_html(entry, original), entry: entry)
    HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{web}</div>").inline_html
  rescue => exception
    Rails.logger.info { "EntryRendering diff failed entry=#{entry.id} #{exception.inspect}" }
    nil
  end

  # Everything stored that a rendering is derived from. Settings and data
  # matter too, but change only through saves, which re-render.
  def self.inputs_crc(entry)
    Zlib.crc32(entry.compressed_original_content.to_s, Zlib.crc32(entry.content.to_s))
  end

  def self.encode(versions, content:, crc:)
    payload = VERSIONS.flat_map { [versions[it].to_s.bytesize, versions[it].to_s.b] }.pack(PACKING)
    [LAYOUT, crc].pack("CN") + Zstd.compress(payload, level: 3, **dictionary(content))
  end

  def self.decode(blob, content:)
    layout = blob.getbyte(0)
    raise ArgumentError, "unknown EntryRendering layout #{layout.inspect}" unless layout == LAYOUT
    payload = Zstd.decompress(blob.byteslice(5..), **dictionary(content))
    offset = 0
    VERSIONS.to_h do |name|
      length = payload.unpack1("N", offset: offset)
      value = payload.byteslice(offset + 4, length).force_encoding(Encoding::UTF_8)
      offset += 4 + length
      [name, (value.empty? && %i[full diff].include?(name)) ? nil : value]
    end
  end

  def self.dictionary(content)
    content.present? ? {dict: content} : {}
  end

  def self.build(entry)
    versions = versions_for(entry)
    new(entry: entry, version: ContentFormatter::VERSION, blob: encode(versions, content: entry.content, crc: inputs_crc(entry))).tap do
      it.instance_variable_set(:@versions, versions)
    end
  end

  def self.render!(entry)
    build(entry).tap { upsert({entry_id: it.entry_id, version: it.version, blob: it.blob}, unique_by: :entry_id) }
  end

  def layout
    blob.getbyte(0)
  end

  def crc
    blob.byteslice(1, 4).unpack1("N")
  end

  def current_for?(entry)
    layout == LAYOUT && version == ContentFormatter::VERSION && crc == self.class.inputs_crc(entry)
  end

  VERSIONS.each do |name|
    define_method(name) { versions[name] }
  end

  private

  def versions
    @versions ||= self.class.decode(blob, content: entry.content)
  end
end
