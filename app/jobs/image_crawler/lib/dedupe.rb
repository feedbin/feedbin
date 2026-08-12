module ImageCrawler
  # Attaches an entry to an already-stored unified image so the same
  # original_url is never downloaded or processed twice. The legacy S3 object
  # is still copied per entry (EntryDeleter deletes per-entry legacy objects);
  # the R2 object is shared and refcounted by images rows.
  class Dedupe
    attr_reader :record

    def self.attach(original_url, image)
      new(original_url, image).attach
    end

    def initialize(original_url, image)
      @original_url = original_url.to_s
      @image = image
      @record = ::Image.entry_images.find_by(url_fingerprint: ::Image.url_fingerprint_for(@original_url))
    end

    # Returns true when the entry was attached to an existing image and the
    # callback was enqueued. False means: download the candidate normally.
    def attach
      return false if record.nil?

      legacy_url = copy_legacy_object
      return false if legacy_url.nil?

      attached = nil
      ::Image.with_url_lock(record.url_fingerprint) do
        # If GC removed the last reference (and the R2 object) between our
        # lookup and here, we must not reference a deleted object.
        if ::Image.entry_images.where(url_fingerprint: record.url_fingerprint).exists?
          attached = ::Image.attach!(
            provider: @image.provider,
            provider_id: @image.provider_id,
            feed_id: @image.feed_id,
            url: @original_url,
            image_fingerprint: record.image_fingerprint,
            storage_path: record.storage_path,
            width: record.width,
            height: record.height,
            bytesize: record.bytesize,
            placeholder_color: record.placeholder_color,
            data: {
              "legacy_storage_url" => legacy_url,
              "preset"             => @image.preset_name,
              "final_url"          => final_url
            }
          )
        end
      end
      return false if attached.nil?

      @image.original_url      = @original_url
      @image.final_url         = final_url
      @image.storage_url       = legacy_url
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

    # Same mechanics as the legacy DownloadCache#copy_image: give this entry
    # its own copy of the processed S3 object so per-entry legacy deletion
    # stays valid during the transition.
    def copy_legacy_object
      source_url = record.data["legacy_storage_url"]
      return nil if source_url.blank?

      url = URI.parse(source_url)
      source_object_name = url.path[1..-1]
      @image.processed_extension = File.extname(source_object_name).delete(".")
      destination = @image.image_name
      Fog::Storage.new(STORAGE).copy_object(@image.bucket, source_object_name, @image.bucket, destination, @image.storage_options)
      url.path = "/#{destination}"
      url.to_s
    rescue Excon::Error::NotFound
      nil
    end
  end
end
