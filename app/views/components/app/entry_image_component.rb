module App
  class EntryImageComponent < ApplicationComponent
    def initialize(entry)
      @entry = entry
    end

    def view_template
      span class: "relative block entry-image-wrap" do
        if @entry.embed_duration.present?
          span class: "bg-black/40 py-1 px-2 rounded-lg font-bold backdrop-blur absolute z-[2] bottom-2 right-2 absolute text-midnight-700" do
            seconds_to_timestamp(@entry.embed_duration)
          end
        end
        if comparison?
          comparison_images
        else
          span class: "entry-image" do
            span data: {src: @entry.processed_image}, style: placeholder_style
          end
        end
      end
    end

    private

    # Development-only: while the pipeline dual-writes, show the legacy S3
    # jpg and the R2 webp stacked so the two encodings can be compared
    # directly in the entries list.
    def comparison?
      Rails.env.development? &&
        @entry.legacy_processed_image.present? &&
        @entry.r2_processed_image.present? &&
        @entry.legacy_processed_image != @entry.r2_processed_image
    end

    def comparison_images
      span class: "flex flex-col gap-1" do
        variant_image(@entry.legacy_processed_image, "s3 jpg")
        variant_image(@entry.r2_processed_image, "r2 webp")
      end
    end

    # The label must stay outside .entry-image: feedbin.imagePlaceholders
    # replaces that element's first child with the loaded <img>.
    def variant_image(src, label)
      span class: "relative block" do
        span(class: "absolute top-1 left-1 z-[2] rounded bg-black/50 px-1 text-[10px] font-bold text-white") { label }
        span class: "entry-image" do
          span data: {src: src}, style: placeholder_style
        end
      end
    end

    def placeholder_style
      @entry.placeholder_color ? "background-color: ##{@entry.placeholder_color}" : ""
    end
  end
end
