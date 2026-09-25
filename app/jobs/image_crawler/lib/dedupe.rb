module ImageCrawler
  # Attaches an entry to an already-stored image so the same
  # original_url is never downloaded or processed twice. Attaching is purely
  # a database operation: the new row shares the stored object with the rows
  # that already reference it. SweepStoredImages refcounts by storage_path,
  # so shared objects live as long as their last row.
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

      # No liveness re-check: the row we found is the reference, and the
      # sweep only deletes paths with no rows at sweep time.
      # kind is the new row's own: the shared object says nothing about
      # what the picture is to this row's caller.
      ::Image.attach!(
        provider: @image.provider,
        provider_id: @image.provider_id,
        kind: @image.kind,
        feed_id: @image.feed_id,
        url: @original_url,
        **::Image.stored_object_attributes(record),
        data: {
          "preset"    => @image.preset_name,
          "final_url" => record.final_url.presence || @original_url
        }
      )

      @image.original_url = @original_url
      @image.enqueue_callback
      true
    end
  end
end
