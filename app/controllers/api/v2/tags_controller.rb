module Api
  module V2
    class TagsController < ApiController
      respond_to :json

      def index
        @user = current_user
        @tags = @user.feed_tags
      end

      def update
        user = current_user

        tag = Tag.find_by_name(params[:old_name])
        Tag.rename(user, tag, params[:new_name])

        @taggings = user.taggings.includes(:tag)
      end

      def destroy
        user = current_user
        tag = Tag.find_by_name(params[:name])

        Tag.destroy(user, tag)

        @taggings = user.taggings.includes(:tag)
      end
    end
  end
end
