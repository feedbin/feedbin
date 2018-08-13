module Api
  module V2
    class TagsController < ApiController
      respond_to :json

      def index
        @user = current_user
        @tags = @user.feed_tags
      end
    end
  end
end
