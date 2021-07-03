module Api
  module V2
    class SavedSearchesController < ApiController
      respond_to :json

      before_action :validate_content_type, only: [:create]
      before_action :validate_create, only: [:create]

      def index
        @user = current_user
        @saved_searches = @user.saved_searches.order(Arel.sql("lower(name)"))
        if @saved_searches.present?
          fresh_when(etag: @saved_searches.map(&:id), last_modified: @saved_searches.maximum(:updated_at))
        else
          @saved_searches = []
        end
      end

      def show
        @user = current_user
        saved_search = @user.saved_searches.where(id: params[:id]).first

        if saved_search.present?
          limit = 1_000
          params[:query] = saved_search.query
          page = params[:page] || 1
          per_page = params[:per_page] = if params[:include_entries] == "true"
            100
          else
            limit
          end

          @entries = Entry.scoped_search(params, @user)

          page_data = @entries
          if @entries.total_entries > limit
            page_data = WillPaginate::Collection.create(page, per_page, limit) { |pager| pager.replace((1..limit).to_a) }
          end
          
          if @entries.total_entries == 0 || page_data.out_of_bounds?
            render(json: []) and return 
          end

          entry_count(page_data)
          links_header(page_data, "api_v2_saved_search_url", saved_search.id)

          if params[:include_entries] != "true"
            render json: @entries.results.map { |entry| entry.id.to_i }.to_json
          end
        else
          status_forbidden
        end
      rescue Elasticsearch::Transport::Transport::Errors::InternalServerError
        render(json: [], status: 404)
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
          head :no_content
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
        needs_nested params[:saved_search], "query", "name"
      end

      def out_of_bounds?
        @entries.respond_to?(:out_of_bounds?) && @entries.out_of_bounds? || (params[:page] && params[:page].to_i > 5)
      end
    end
  end
end
