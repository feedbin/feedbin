module App
  class FeedStatsComponent < ApplicationComponent
    def initialize(feed:, stats:)
      @feed = feed
      @stats = stats
    end

    def view_template
      div class: "flex gap-4 items-baseline" do
        p(class: "grow text-sm one-line text-600", title: @feed.feed_url) do
          helpers.display_url(@feed.feed_url)
        end
        div class: "" do
          Sparkline(sparkline: ::Sparkline.new(width: 80, height: 15, stroke: 1, percentages: @stats[@feed.id].percentages), theme: true)
        end
      end

      div class: "flex gap-4 items-baseline text-xs mt-1" do
        p(class: "text-ellipsis one-line grow min-w-0", title: @feed.feed_description) do
          @feed.feed_description
        end
        p(class: "shrink-0") do
          plain helpers.timeago(@feed.last_published_entry, prefix: "Latest article:")
          plain ", #{helpers.number_with_delimiter(@stats[@feed.id].volume)}/mo"
        end
      end
    end
  end
end
