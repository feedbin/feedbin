module Api
  module V2
    class SavedSearchesController < ApiController

      respond_to :json

      before_action :validate_content_type, only: [:create]
      before_action :validate_create, only: [:create]

      def index
        @user = current_user
        @saved_searches = @user.saved_searches.order("lower(name)")
        if @saved_searches.any?
          fresh_when(etag: @saved_searches, last_modified: @saved_searches.maximum(:updated_at))
        else
          @saved_searches = []
        end
      end

      def show
        @user = current_user
        saved_search = @user.saved_searches.where(id: params[:id]).first

        if saved_search.present?
          params[:query] = saved_search.query
          if params[:include_entries] && params[:include_entries] == "true"
            @entries = Entry.search(params, @user)
            links_header(@entries, 'api_v2_saved_search_url', saved_search.id)
          else
            params[:load] = false
            entries = Entry.search(params, @user)
            links_header(entries, 'api_v2_saved_search_url', saved_search.id)
            render json: entries.results.map {|entry| entry.id.to_i}.to_json
          end
        else
          status_forbidden
        end

      end

      def create
        @user = current_user
        @saved_search = @user.saved_searches.create(saved_search_params)
        render status: :created, location: api_v2_saved_search_url(@saved_search, format: :json)
      end

      def destroy
        @user = current_user
        @saved_search = @user.saved_searches.where(id: params[:id]).first
        if @saved_search.present?
          @saved_search.destroy
          render nothing: true, status: :no_content
        else
          status_forbidden
        end
      end

      def update
        @user = current_user
        @saved_search = @user.saved_searches.where(id: params[:id]).first
        if @saved_search.present?
          @saved_search.update(saved_search_params)
        else
          status_forbidden
        end
      end

      private

      def saved_search_params
        params.require(:saved_search).permit(:query, :name)
      end

      def validate_create
        needs 'query', 'name'
      end

    end
  end
end