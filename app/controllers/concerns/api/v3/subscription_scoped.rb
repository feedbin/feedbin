module Api
  module V3
    module SubscriptionScoped
      extend ActiveSupport::Concern

      private

      def set_subscription
        @subscription = subscription_list.find(params[:subscription_id] || params[:id])
      end

      def subscription_list
        @subscription_list ||= SubscriptionList.new(@user)
      end
    end
  end
end
