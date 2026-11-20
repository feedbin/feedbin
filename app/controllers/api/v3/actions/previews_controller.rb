module Api
  module V3
    module Actions
      # A dry run of a rule that isn't saved: what the Actions page's View Results shows while the rule is edited.
      class PreviewsController < ApiController
        include SearchPage

        def create
          action = ActionWrite.new(@user, @user.actions.new, rule, required: false).apply
          render_search_page(EntrySearch.new(@user, query: action.query.to_s, feed_ids: action.scoped_feed_ids))
        end

        private

        # A rule with no scope covers every feed, as a new action does.
        def rule
          body.reverse_merge("feed_ids" => [], "tag_ids" => []).except("title", "mark_existing_read")
        end
      end
    end
  end
end
