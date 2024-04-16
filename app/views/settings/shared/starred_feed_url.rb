module Settings
  module Shared
    class StarredFeedUrl < ApplicationComponent
      def initialize(user:)
        @user = user
      end

      def view_template
        if @user.setting_on?(:starred_feed_enabled)
          div class: "truncate" do
            plain "Feed URL: "
            link_to helpers.starred_url(@user.starred_token, format: :xml), helpers.starred_url(@user.starred_token, format: :xml)
          end
        else
          plain "For "
          link_to "/blog/2013/04/10/starred-entry-feed/" do
            "integrating with other services"
          end
          plain "."
        end
      end
    end
  end
end
