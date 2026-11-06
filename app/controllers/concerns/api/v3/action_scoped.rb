module Api
  module V3
    module ActionScoped
      extend ActiveSupport::Concern

      private

      def set_action
        @action = actions.find(params[:action_id] || params[:id])
      end

      # nil action_type: legacy rows from before the column default (standard).
      def actions
        @user.actions.where(action_type: [nil, *ActionWrite::KINDS])
      end
    end
  end
end
