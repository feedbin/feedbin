module Api
  module V3
    class TagsController < ApiController
      before_action :set_tag, only: [:update, :destroy]

      def index
        data = tags.each_with_subscription_ids.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h }
        return if not_modified?(etag_for("tags", digest(data)))
        render_list(data)
      end

      # Renaming can change the id or merge into an existing tag; nil means the name is unusable.
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
