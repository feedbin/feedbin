module App
  class EntryImageComponent < ApplicationComponent
    def initialize(entry)
      @entry = entry
    end

    def view_template
      span class: "relative block" do
        if @entry.embed_duration.present?
          span class: "bg-black/40 py-1 px-2 rounded-lg font-bold backdrop-blur absolute z-10 bottom-2 right-2 absolute text-midnight-700" do
            seconds_to_timestamp(@entry.embed_duration)
          end
        end
        span class: "entry-image" do
          span data: {src: @entry.processed_image}, style: @entry.placeholder_color ? "background-color: ##{@entry.placeholder_color}" : ""
        end
      end
    end
  end
end
