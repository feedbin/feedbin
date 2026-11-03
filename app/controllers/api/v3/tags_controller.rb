module Api
  module V3
    # GET /tags, PATCH /tags/{id}, DELETE /tags/{id}.
    class TagsController < ApiController
      def index
        data = tags.each_with_subscription_ids.map { |tag, ids| TagSerializer.new(tag, subscription_ids: ids).to_h }
        return if not_modified?(etag_for("tags", digest(data)))
        render_list(data)
      end

      # Renaming usually changes the id, and a name the user already has
      # merges the two. Tag.rename returns nil when the name cannot be used.
      def update
        tag = tags.find(params[:id])
        name = request.request_parameters["name"]
        unless name.is_a?(String) && name.strip.present?
          raise Problems::InvalidParameter.new("name is required.", pointer: "/name", code: "missing")
        end
        renamed = Tag.rename(@user, tag, name) or raise Problems::InvalidParameter.new("name cannot be used as a tag.", pointer: "/name", code: "invalid_value")
        render json: tags.serialize(renamed)
      end

      def destroy
        Tag.destroy(@user, tags.find(params[:id]))
        head :no_content
      end

      private

      def tags
        @tags ||= TagList.new(@user)
      end
    end
  end
end
