module Api
  module V3
    # Action rules: the list with an ETag, create, update and delete
    # (ActionWrite). A rule's preview is Actions::EntriesController.
    class ActionsController < ApiController
      include ActionScoped

      before_action :set_action, only: [:update, :destroy]

      def index
        data = actions.order(Arel.sql("lower(title)"), :id).map { ActionSerializer.new(_1).to_h }
        return if not_modified?(etag_for("actions", digest(data)))
        render_list(data)
      end

      def create
        action = ActionWrite.new(@user, @user.actions.new, body, required: true).apply
        render_saved(action, status: :created)
      end

      def update
        ActionWrite.new(@user, @action, body, required: false).apply
        render_saved(@action, status: :ok)
      end

      def destroy
        @action.destroy
        head :no_content
      end

      private

      # The one base error besides bad syntax is a scope with no feeds left
      # in it.
      def render_saved(action, status:)
        if action.save
          render json: ActionSerializer.new(action).to_h, status: status
        elsif action.errors.added?(:base, "Search syntax invalid")
          status_query_invalid
        else
          status_validation_failed(record_errors(action, base: "feed_ids"))
        end
      end
    end
  end
end
