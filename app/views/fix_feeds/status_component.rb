module FixFeeds
  class StatusComponent < ApplicationComponent

    def initialize(count:, replace_path:, remote: false)
      @count = count
      @replace_path = replace_path
      @remote = remote
    end

    def view_template
      div(class: "flex gap-4 justify-between items-center mb-8", data: {behavior: "status_component"}) do
        div do
          h3 class: "text-700 font-bold" do
            "Fixable Feeds"
          end
          render Count.new(count: @count)
        end
        link_to "Replace All", @replace_path, class: "button", method: :post, remote: @remote
      end
    end

    class Count < ApplicationComponent
      def initialize(count:)
        @count = count
      end

      def view_template
        p(class: "text-sm text-500", data: {behavior: "status_count_component"}) do
          plain number_with_delimiter(@count)
          plain " alternative".pluralize(@count)
          plain " available"
        end
      end
    end
  end
end
