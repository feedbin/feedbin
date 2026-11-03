module Api
  module V3
    # Saved searches: the list with an ETag, and create, update and delete.
    # The query is validated with Elasticsearch before it is stored.
    class SavedSearchesController < ApiController
      before_action :set_saved_search, only: [:update, :destroy]

      def index
        data = @user.saved_searches.order(Arel.sql("lower(name)")).map { SavedSearchSerializer.new(_1).to_h }
        return if not_modified?(etag_for("saved_searches", digest(data)))
        render_list(data)
      end

      def create
        render_saved(@user.saved_searches.new(saved_search_params(required: true)), status: :created)
      end

      def update
        @saved_search.assign_attributes(saved_search_params(required: false))
        render_saved(@saved_search, status: :ok)
      end

      def destroy
        @saved_search.destroy
        head :no_content
      end

      private

      def set_saved_search
        @saved_search = @user.saved_searches.find(params[:id])
      end

      # title is the name column.
      def saved_search_params(required:)
        attributes = {}
        attributes[:name] = required_string("title") if required || body.key?("title")
        attributes[:query] = required_string("query") if required || body.key?("query")
        attributes
      end

      def render_saved(saved_search, status:)
        if saved_search.save
          render json: SavedSearchSerializer.new(saved_search).to_h, status: status
        elsif saved_search.errors[:query].any?
          status_query_invalid
        else
          status_validation_failed(record_errors(saved_search, name: "title"))
        end
      end
    end
  end
end
