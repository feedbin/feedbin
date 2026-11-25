module Api
  module V3
    module Account
      # Takes a subscription that is live on another account, for the signed-in one.
      class StoreSubscriptionTransfersController < ApiController
        include StoreSubscriptionProof

        rescue_from StoreSubscription::MovedTooRecently, with: :render_moved_too_recently

        def create
          @user.take_store_subscription(**proof_params)
          render json: AccountSerializer.new(@user.reload).to_h
        end

        private

        def render_moved_too_recently
          render_problem :conflict, "store_subscription_moved_recently",
            title: "Moved too recently",
            detail: "This subscription was moved in the last #{StoreSubscription::MOVE_INTERVAL.in_days.to_i} days."
        end
      end
    end
  end
end
