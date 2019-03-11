module Api
  module V2
    class ActionsController < ApiController
      respond_to :json

      before_action :set_action, only: [:update, :results]
      before_action :validate_content_type, only: [:create]
      skip_before_action :valid_user

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
        @action = @user.actions.build(action_params)
        @action.all_feeds = all_feeds?(action_params)
        @action.automatic_modification = true
        @action.save
      end

      def update
        @action.all_feeds = all_feeds?(action_params)
        unless @action.update(action_params)
          head :bad_request
        end
      end

      def results
        @user = current_user

        query = {}
        if @action.query.present?
          query[:query] = @action.query
        end

        if @action.computed_feed_ids.present?
          query[:feed_ids] = @action.computed_feed_ids
          if params[:read].present?
            query[:read] = params[:read] == "true"
          end
          @entries = Entry.scoped_search(query, @user)
        else
          @entries = []
        end
      end

      def results_watch
        @user = current_user

        if action = @user.actions.notifier.take
          query = {}
          if action.query.present?
            query[:query] = action.query
          end
          if action.computed_feed_ids.present?
            query[:feed_ids] = action.computed_feed_ids
            query[:read] = false
            @entries = Entry.scoped_search(query, @user).limit(10).includes(:feed)
            @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) { |(feed_id, title), hash|
              hash[feed_id] = title
            }
          else
            @entries = []
          end
        else
          @entries = []
        end
      end

      private

      def action_params
        params.require(:action_params).permit(:query, :action_type, :feed_ids, :tag_ids, feed_ids: [], tag_ids: [], actions: [])
      end

      def set_action
        @action = current_user.actions.find(params[:id])
      end

      def all_feeds?(action)
        action[:feed_ids].blank? && action[:tag_ids].blank?
      end
    end
  end
end
