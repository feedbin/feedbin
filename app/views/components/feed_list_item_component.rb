class FeedListItemComponent < ApplicationComponent
  def initialize(feed:)
    @feed = feed
  end

  def view_template
    div class: "flex items-start p-4 rounded-xl bg-white shadow-md border border-gray-200" do
      div class: "w-12 h-12 shrink-0 mr-4" do
        # img src: @feed.favicon_url, class: "w-full h-full object-contain rounded"
        FaviconComponent.new(feed:@feed, entry:nil)
      end
      div class: "flex flex-col justify-center overflow-hidden" do
        div class: "font-semibold text-gray-900 truncate" do
          @feed.title || "无标题"
        end
        div class: "text-sm text-gray-600 mt-1 line-clamp-2" do
          @feed.site_url || "无描述信息"
        end
      end
    end
  end
end