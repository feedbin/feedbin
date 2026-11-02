# Every formatted version of one entry, stored so a read serves bytes instead
# of running ContentFormatter. The blob is a 5-byte header (layout version,
# CRC32 of the inputs) and one zstd frame compressed with the entry's content
# as its dictionary, so a version costs little beyond what differs from the
# content. A row whose VERSION or CRC does not match its entry is stale and
# is rendered again (Entry#rendering).
#
# What the versions are and how each is made from an entry is
# ContentFormatter's business; this class only keeps them.
class EntryRendering < ApplicationRecord
  self.primary_key = :entry_id

  belongs_to :entry, inverse_of: :rendering_record

  LAYOUT = 3
  VERSIONS = ContentFormatter::VERSIONS
  # Each version is a 4-byte length and its bytes, in VERSIONS order. A
  # version the entry doesn't have (full for an article, diff for an unedited
  # entry, extracted for one without saved pages) is stored as ABSENT with no bytes, so nil survives the round trip.
  PACKING = "Na*" * VERSIONS.size
  ABSENT = 0xFFFFFFFF

  # Loading a relation extended with this also stores the renderings its
  # entries are missing, in one write, before the records come back. Reads
  # that don't load (pluck, count, an ETag check) do no rendering. Entries
  # must come with rendering_record preloaded; Entry.with_renderings does
  # both.
  module PrepareOnLoad
    def load(&block)
      return self if loaded?
      super
      EntryRendering.prepare(records)
      self
    end
  end

  # Everything stored that a rendering is derived from. Settings and data
  # matter too, but change only through saves, which re-render. The Camo
  # host and key are in it because every proxied image URL is signed with
  # them: a rotated key makes every stored rendering stale.
  def self.inputs_crc(entry)
    seed = Zlib.crc32("#{ENV["CAMO_HOST"]}\0#{ENV["CAMO_KEY"]}")
    seed = Zlib.crc32(entry.content.to_s, seed)
    Zlib.crc32(entry.compressed_original_content.to_s, seed)
  end

  def self.encode(versions, content:, crc:)
    payload = VERSIONS.flat_map do |name|
      value = versions[name]
      value.nil? ? [ABSENT, ""] : [value.bytesize, value.to_s.b]
    end.pack(PACKING)
    [LAYOUT, crc].pack("CN") + Zstd.compress(payload, level: 3, **dictionary(content))
  end

  def self.decode(blob, content:)
    layout = blob.getbyte(0)
    raise ArgumentError, "unknown EntryRendering layout #{layout.inspect}" unless layout == LAYOUT
    payload = Zstd.decompress(blob.byteslice(5..), **dictionary(content))
    offset = 0
    VERSIONS.to_h do |name|
      length = payload.unpack1("N", offset: offset)
      offset += 4
      next [name, nil] if length == ABSENT
      value = payload.byteslice(offset, length).force_encoding(Encoding::UTF_8)
      offset += length
      [name, value]
    end
  end

  def self.dictionary(content)
    content.present? ? {dict: content} : {}
  end

  # Unsaved. The entry is attached without going through the inverse: that
  # would make the record the entry's loaded rendering_record, which Rails
  # then autosaves on the entry's next save, inserting a row upsert wrote.
  def self.build(entry)
    versions = ContentFormatter.versions(entry)
    new(entry_id: entry.id, version: ContentFormatter::VERSION, blob: encode(versions, content: entry.content, crc: inputs_crc(entry))).tap do
      it.association(:entry).target = entry
      it.instance_variable_set(:@versions, versions)
    end
  end

  def self.render!(entry)
    build(entry).tap(&:store!)
  end

  # Renders the entries whose stored row is missing or stale and stores them
  # in one upsert, so a page of cold entries costs one write, not one each.
  # Callers preload :rendering_record. An entry that fails to render is
  # reported and left out, and its own read raises as it would have anyway;
  # the rest of the batch is still stored. Each entry keeps its rendering
  # even if the write fails; the next read renders and tries again.
  def self.prepare(entries)
    built = entries.reject { it.new_record? || it.rendering_record&.current_for?(it) }.uniq(&:id).filter_map do |entry|
      build(entry).tap { entry.rendering = it }
    rescue => exception
      ErrorService.notify(
        error_class: "EntryRendering.prepare",
        error_message: "rendering failed",
        parameters: {entry_id: entry.id, exception: exception}
      )
      nil
    end
    return if built.empty?
    write(built)
  rescue => exception
    ErrorService.notify(
      error_class: "EntryRendering.prepare",
      error_message: "storing renderings failed",
      parameters: {entry_ids: built&.map(&:entry_id), exception: exception}
    )
  end

  # Storing is optional: a row that isn't written is rendered again on the
  # next read. So a write waits half a second for a row another write holds,
  # not the connection's lock timeout, and rows go in entry id order so two
  # batches that share entries can't deadlock.
  def self.write(renderings)
    transaction do
      connection.execute("SET LOCAL lock_timeout = '500ms'")
      rows = renderings.sort_by(&:entry_id).map { {entry_id: it.entry_id, version: it.version, blob: it.blob} }
      upsert_all(rows, unique_by: :entry_id)
    end
  end

  def store!
    self.class.write([self])
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

  # The extracted version as URL => HTML, empty when there are no pages.
  def extracted_pages
    @extracted_pages ||= extracted ? JSON.parse(extracted) : {}
  end

  private

  def versions
    @versions ||= self.class.decode(blob, content: entry.content)
  end
end
