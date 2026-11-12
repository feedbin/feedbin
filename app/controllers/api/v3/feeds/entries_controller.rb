module Api
  module V3
    module Feeds
      class EntriesController < ApiController
        include FeedScoped
        include Timeline

        before_action :set_feed

        def index
          render_timeline
        end

        private

        def timeline_base
          @feed.entries
        end

        def streams?
          false
        end

        # One feed is read in order through its own index.
        def windowed?
          false
        end
      end
    end
  end
end
