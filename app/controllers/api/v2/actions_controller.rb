module Api
  module V2
    class ActionsController < ApiController

      respond_to :json

      before_action :set_action, only: [:update, :results]
      before_action :validate_content_type, only: [:create]

      def index
        @user = current_user
        @actions = @user.actions
        if params[:action_type].present?
          action_type = params[:action_type].to_sym
          @actions = @actions.where(action_type: Action.action_types[action_type])
        end
      end

      def create
        @user = current_user
        @action = @user.actions.create(action_params)
      end

      def update
        if !@action.update(action_params)
          render nothing: true, status: :bad_request
        end
      end

      def results
        @user = current_user
        query = {}
        if @action.query.present?
          query[:query] = @action.query
        end
        if @action.computed_feed_ids.any?
          query[:feed_ids] = @action.computed_feed_ids
        end

        if query.length > 0
          query[:read] = false
          @entries = Entry.search(query, @user)
        else
          @entries = []
        end

      end

      private

      def action_params
        params.require(:action_params).permit(:query, :action_type, :feed_ids => [], :tag_ids => [], :actions => [])
      end

      def set_action
        @action = current_user.actions.find(params[:id])
      end

    end
  end
end


