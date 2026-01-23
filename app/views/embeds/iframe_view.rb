module Embeds
  class IframeView < ApplicationView

    STIMULUS_CONTROLLER = :embed_player

    def initialize(media:, width:, height:)
      @media = media
      @width = width
      @height = height
      @expandable_selector = "expandable_#{SecureRandom.hex}"
    end

    def view_template
      controller = stimulus(
        controller: STIMULUS_CONTROLLER,
        outlets: {
          expandable: "[data-#{@expandable_selector.dasherize}]",
        },
        values: {
          source_url: @media.iframe_src,
          width: @width,
          height: @height,
          loaded: "false",
          chapters_open: "false",
          has_image: @media.image_url.present?.to_s,
          youtube: @media.youtube?.to_s
        }
      )
      div class: "group system-content text-[14px] text-midnight-500 other mb-[1.1em]", data: controller do
        image

        div class: "bg-midnight-100 rounded-b-lg group-data-[embed-player-has-image-value=false]:rounded-lg" do
          embed_info
          chapters
        end
        template data: stimulus_item(target: :iframe_template, for: STIMULUS_CONTROLLER) do
          iframe data: stimulus_item(target: :iframe, for: STIMULUS_CONTROLLER), src: @media.iframe_src, class: "w-full h-full border-none", allow: "accelerometer autoplay clipboard-write encrypted-media gyroscope picture-in-picture", allowfullscreen: true
        end
      end
    end

    def image
      div class: "z-30 relative transition transition-[top] w-full h-0 bg-black pt-[56.25%] group-data-[embed-player-chapters-open-value=true]:sticky group-data-[embed-player-chapters-open-value=true]:top-[43px] group-data-[embed-player-has-image-value=false]:tw-hidden group-[.hide-entry-column-toolbar]/body:!top-0" do
        button data: stimulus_item(target: :play_button, actions: {click: :show_player}, for: STIMULUS_CONTROLLER), class: "absolute group/play-button cursor-pointer inset-x-0 inset-y-0 flex flex-center z-20 cursor-pointer group-data-[embed-player-loaded-value=true]:tw-hidden" do
          div class: "w-[80px] h-[45px] tw-hidden group-hover/play-button:flex rounded-lg flex-center backdrop-blur-md bg-black/50" do
            Icon("icon-play", class: "fill-white")
          end
          div class: "bg-black/40 py-1 px-2 rounded-lg font-bold backdrop-blur bottom-2 right-2 absolute text-midnight-700" do
            seconds_to_timestamp(@media.duration)
          end
        end

        div data: stimulus_item(target: :video_container, for: STIMULUS_CONTROLLER), class: "flex flex-center absolute inset-x-0 inset-y-0 z-10" do
          img src: camo_link(@media.image_url), class: "responsive max-w-full max-h-full !m-0"
        end
      end
    end

    def embed_info
      div class: "flex items-center !leading-[1]" do
        a data: stimulus_item(actions: {click: :swap_iframe}, for: STIMULUS_CONTROLLER), class: "flex items-center gap-3 sm:gap-4 p-3 sm:p-4 grow min-w-0", href: @media.canonical_url, title: "Visit Embed Source" do
          div class: "flex flex-center sm:w-[48px] sm:h-[48px] w-[36px] h-[36px] shrink-0 place-self-start" do
            if @media.profile_image
              img src: RemoteFile.signed_url(@media.profile_image), class: "responsive !m-0 !max-w-full rounded-full"
            else
              Icon("icon-embed-source-#{@media.clean_name}", class: "max-w-full h-auto fill-midnight-500")
            end
          end
          div class: "flex grow min-w-0" do
            div class: "flex flex-col gap-1" do
              div class: "font-bold two-lines m-0 !leading-[1.3] text-midnight-700" do
                @media.title.present? ? @media.title : "Load Embed"
              end
              if @media.channel_name
                div class: "text-midnight-700" do
                  @media.channel_name
                end
              end
              div class: "text-midnight-600" do
                @media.subtitle
              end
            end
          end
        end
        if @media.chapters.present?
          button title: "Show Chapters", class: "flex flex-center place-self-stretch font-bold p-3 sm:p-4 pl-0 text-midnight-700", data: stimulus_item(actions: {click: :toggle_chapters}, for: STIMULUS_CONTROLLER) do
            div class: "p-2 rounded flex items-center gap-2 transistion bg-midnight-200 group-data-[embed-player-chapters-open-value=true]:bg-midnight-300" do
              Icon("icon-chapters", class: "fill-midnight-600")
              span do
                number_with_delimiter(@media.chapters.count)
              end
            end
          end
        end
      end
    end


    def chapters
      if @media.chapters.present?
        render App::ExpandableContainerComponent.new(selector: @expandable_selector) do |expandable|
          expandable.content do
            div class: "flex flex-col gap-1 p-3 sm:p-4 text-midnight-600" do
              div class: "px-3 sm:px-4 font-bold text-midnight-700" do
                "Chapters"
              end
              div class: "flex flex-col overflow-y-scroll overflow-x-hidden snap-x snap-mandatory" do
                @media.chapters.each do |chapter|
                  render ChapterRow.new(chapter: chapter)
                end
              end
            end
          end
        end
      end
    end

    class ChapterRow < ApplicationView
      def initialize(chapter:)
        @chapter = chapter
      end

      def view_template
        button data: stimulus_item(target: :chapter_button, actions: {"click" => "selectChapter"}, params: {seconds: @chapter[:seconds], duration: seconds_to_timestamp(@chapter[:duration])}, for: STIMULUS_CONTROLLER, data: {selected: "false"}), class: " group/chapter-row grow flex flex-center text-left px-3 sm:px-4 rounded py-1 pointer-fine:hover:text-midnight-700 pointer-fine:hover:bg-midnight-200 data-[selected=true]:text-midnight-700 data-[selected=true]:bg-midnight-200" do
          div class: "flex items-center grow min-w-0" do
            div class: "grid overflow-hidden shrink-0 min-w-0 [grid-template-columns:0fr] transition-[grid-template-columns] group-data-[selected=true]/chapter-row:[grid-template-columns:1fr]" do
              div class: "min-w-0 transition opacity-0 group-data-[selected=true]/chapter-row:opacity-100" do
                Icon("icon-mini-play", class: "mr-2 fill-midnight-700")
              end
            end
            div class: "grow min-w-0 one-line text-pretty" do
              @chapter[:title]
            end
          end
          div class: "shrink-0 tabular-nums font-bold", data: {embed_player_duration: true} do
            seconds_to_timestamp(@chapter[:duration])
          end
        end
      end
    end
  end
end
