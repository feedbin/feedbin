module Api
  module V3
    module Actions
      class EntriesController < ApiController
        include ActionScoped
        include SearchPage

        before_action :set_action

        def index
          render_search_page(EntrySearch.new(@user, query: @action.query.to_s, feed_ids: @action.computed_feed_ids))
        end
      end
    end
  end
end
