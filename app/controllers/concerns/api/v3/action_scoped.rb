# Loads @action from the action rules v3 lists.
module Api
  module V3
    module ActionScoped
      extend ActiveSupport::Concern

      private

      def set_action
        @action = actions.find(params[:action_id] || params[:id])
      end

      # NULL is an old row from before the column had a default: standard.
      def actions
        @user.actions.where(action_type: [nil, *ActionWrite::KINDS])
      end
    end
  end
end
