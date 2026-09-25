module ImageCrawler
  class Image
    ATTRIBUTES = %i[
      bytesize
      context
      download_path
      entry_url
      etag
      feed_id
      final_url
      fingerprint
      height
      id
      image_urls
      kind
      last_modified
      meta_image_urls
      original_fingerprint
      original_url
      page_url
      placeholder_color
      preset_name
      processed_path
      provider
      provider_id
      width
    ]

    attr_accessor(*ATTRIBUTES)

    CONTENT_TYPES = {
      "png" => "image/png",
      "jpg" => "image/jpeg"
    }.freeze

    # A rendering recipe. A content_addressed preset keys its stored object
    # on the original bytes instead of the url (see storage_path). job_class
    # is the callback that runs once the row lands; a preset without one
    # stores the row and stops.
    Preset = Data.define(:width, :height, :crop, :format, :minimum_size, :validate, :content_addressed, :job_class) do
      def initialize(width:, height:, crop:, format:, minimum_size: nil, validate: false, content_addressed: false, job_class: nil)
        super
      end

      # Identity pairs variant with the url (entry presets) or
      # original_fingerprint (content-addressed presets), plus the format as
      # extension. All three must match to share an object: podcast and
      # touch_icon both render 200x200 and only the format separates them.
      def variant
        "#{width}x#{height}"
      end
    end

    PRESETS = {
      primary:          Preset.new(width: 542, height: 304, crop: :smart_crop, format: "jpg", minimum_size: 20_000, validate: true, job_class: EntryImage),
      twitter:          Preset.new(width: 542, height: 304, crop: :smart_crop, format: "jpg", minimum_size: 10_000, validate: true, job_class: TwitterLinkImage),
      youtube:          Preset.new(width: 542, height: 304, crop: :fill_crop,  format: "jpg", validate: true, job_class: EntryImage),
      podcast:          Preset.new(width: 200, height: 200, crop: :fill_crop,  format: "jpg", validate: true, content_addressed: true),
      podcast_feed:     Preset.new(width: 200, height: 200, crop: :fill_crop,  format: "jpg", validate: true, content_addressed: true, job_class: ItunesFeedImage),
      channel_avatar:   Preset.new(width: 200, height: 200, crop: :limit_png,  format: "png", content_addressed: true, job_class: ChannelImage),
      feed_icon:        Preset.new(width: 200, height: 200, crop: :limit_png,  format: "png", content_addressed: true, job_class: FeedIcon),
      micropost_avatar: Preset.new(width: 200, height: 200, crop: :limit_png,  format: "png", content_addressed: true, job_class: MicropostAvatar),
      favicon:          Preset.new(width: 32,  height: 32,  crop: :icon_crop,  format: "png", content_addressed: true),
      touch_icon:       Preset.new(width: 200, height: 200, crop: :icon_crop,  format: "png", content_addressed: true)
    }.freeze

    # kind is required alongside preset_name because they answer different
    # questions: the preset is the rendering recipe, kind is what the
    # picture is, which only the caller knows. Passed as ::Image.kinds[...]
    # like provider, so the payload carries the enum value.
    def self.new_with_attributes(id:, kind:, preset_name:, image_urls:, provider:, provider_id:, **other)
      new(other.merge(id:, kind:, preset_name:, image_urls:, provider:, provider_id:))
    end

    # Ignores attributes it does not recognize: pipeline jobs are retry: false
    # and run on host-local queues, so a payload written by one deploy must
    # not crash the code of the next.
    def initialize(data = {})
      data.each do |name, value|
        if ATTRIBUTES.include?(name.to_sym)
          instance_variable_set("@#{name}", value)
        end
      end
    end

    def to_h
      ATTRIBUTES.index_with { public_send(it) }
    end

    def preset
      PRESETS.fetch(preset_name.to_sym)
    end

    def validate?
      preset.validate
    end

    # The row is written by now, so the callback needs only to know which
    # one: storage_path and provider_id. The caller's context rides through
    # every stage untouched and comes back here.
    def enqueue_callback
      return if preset.job_class.nil?

      payload = {
        "storage_path" => storage_path,
        "provider_id"  => provider_id.to_s
      }
      payload["context"] = context if context
      preset.job_class.perform_async(id, payload)
    end

    def create_image
      record = ::Image.attach!(
        provider: provider,
        provider_id: provider_id,
        kind: kind,
        feed_id: feed_id,
        url: original_url,
        variant: variant,
        image_fingerprint: fingerprint,
        original_fingerprint: original_fingerprint,
        storage_path: storage_path,
        width: width,
        height: height,
        bytesize: bytesize,
        placeholder_color: placeholder_color,
        data: {
          "preset"        => preset_name,
          "final_url"     => final_url,
          "etag"          => etag,
          "last_modified" => last_modified
        }.compact
      )

      # The row moved objects, so the old one may be unreferenced. Deferred
      # so a concurrent crawl attaching to the old path has written its row
      # by the time the sweep looks.
      if record.saved_change_to_storage_path? && (replaced = record.storage_path_before_last_save)
        SweepStoredImages.perform_in(ImageGarbageCollector::SWEEP_DELAY, [replaced])
      end

      record
    end

    # Hashing a blank fingerprint would put every such image at one shared
    # path, so a content-addressed preset without one raises instead.
    def storage_path
      if content_addressed?
        raise ArgumentError, "content-addressed preset #{preset_name} has no original_fingerprint" if original_fingerprint.blank?
        ::Image.content_storage_path_for(original_fingerprint, variant, preset.format)
      else
        ::Image.storage_path_for(original_url, variant, preset.format)
      end
    end

    # The icon family, podcast art and avatars: storage identity comes from
    # the original bytes rather than the URL, and the pipeline always
    # downloads before deciding anything. The rest are keyed by url, which
    # is what makes Dedupe and ReuseRules meaningful for them.
    def content_addressed?
      preset.content_addressed
    end

    def variant
      preset.variant
    end

    def storage_options
      {
        "Content-Type"  => CONTENT_TYPES.fetch(preset.format),
        "Cache-Control" => "max-age=315360000, public, immutable"
      }
    end

    def trace(message:, metadata: {})
      fields = {public_id: id, preset: preset_name}.merge(metadata)
      Sidekiq.logger.info "Image trace: #{message} #{fields.map { |key, value| "#{key}=#{value}" }.join(" ")}"
    end
  end
end
