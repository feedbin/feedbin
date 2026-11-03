module Api
  module V3
    # GET /tags, PATCH /tags/{id}, DELETE /tags/{id}.
    class TagsController < ApiController
      before_action :set_tag, only: [:update, :destroy]

      def index
        data = tags.each_with_subscription_ids.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h }
        return if not_modified?(etag_for("tags", digest(data)))
        render_list(data)
      end

      # Renaming usually changes the id, and a name the user already has
      # merges the two. Tag.rename returns nil when the name cannot be used.
      def update
        renamed = Tag.rename(@user, @tag, required_string("name")) or raise invalid("name", "invalid_value", "name cannot be used as a tag.")
        render json: tags.serialize(renamed)
      end

      def destroy
        Tag.destroy(@user, @tag)
        head :no_content
      end

      private

      def set_tag
        @tag = tags.find(params[:id])
      end

      def tags
        @tags ||= TagList.new(@user)
      end
    end
  end
end
