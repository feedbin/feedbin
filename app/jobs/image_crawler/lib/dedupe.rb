module ImageCrawler
  # Attaches an entry to an already-stored unified image so the same
  # original_url is never downloaded or processed twice. Attaching is purely
  # a database operation: the new row shares both stored objects — the R2
  # webp and the legacy S3 jpg — with the rows that already reference them.
  # The garbage collector refcounts both by storage_path, so shared
  # objects live exactly as long as their last row.
  class Dedupe
    attr_reader :record

    def self.attach(original_url, image)
      new(original_url, image).attach
    end

    def initialize(original_url, image)
      @original_url = original_url.to_s
      @image = image
      @record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(@original_url, image.variant))
    end

    # Returns true when the entry was attached to an existing image and the
    # callback was enqueued. False means: download the candidate normally.
    def attach
      return false if record.nil?

      attached = nil
      ::Image.with_storage_lock(record.storage_path) do
        # If GC removed the last reference (and the stored objects) between
        # our lookup and here, we must not reference deleted objects. Any
        # provider's row counts: the object, not the URL, is what survives.
        if ::Image.where(storage_path: record.storage_path).exists?
          attached = ::Image.attach!(
            provider: @image.provider,
            provider_id: @image.provider_id,
            feed_id: @image.feed_id,
            url: @original_url,
            variant: record.variant,
            image_fingerprint: record.image_fingerprint,
            storage_path: record.storage_path,
            width: record.width,
            height: record.height,
            bytesize: record.bytesize,
            placeholder_color: record.placeholder_color,
            data: {
              "legacy_storage_url" => record.data["legacy_storage_url"],
              "preset"             => @image.preset_name,
              "final_url"          => final_url
            }
          )
        end
      end
      return false if attached.nil?

      @image.original_url      = @original_url
      @image.final_url         = final_url
      @image.storage_url       = record.data["legacy_storage_url"]
      @image.width             = record.width
      @image.height            = record.height
      @image.bytesize          = record.bytesize
      @image.placeholder_color = record.placeholder_color
      @image.fingerprint       = record.image_fingerprint
      @image.send_to_feedbin
      true
    end

    private

    def final_url
      record.data["final_url"].presence || @original_url
    end
  end
end
