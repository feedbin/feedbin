module FixFeeds
  class StatusComponent < ApplicationComponent

    def initialize(count:, replace_path:)
      @count = count
      @replace_path = replace_path
    end

    def view_template
      div(class: "flex gap-4 justify-between items-center mb-8", data: {behavior: "status_component"}) do
        div do
          h3 class: "text-700 font-bold" do
            "Fixable Feeds"
          end
          p(class: "text-sm text-500") do
            plain number_with_delimiter(@count)
            plain " alternative".pluralize(@count)
            plain " available"
          end
        end
        link_to "Replace All", @replace_path, class: "button", method: :post
      end
    end
  end
end
