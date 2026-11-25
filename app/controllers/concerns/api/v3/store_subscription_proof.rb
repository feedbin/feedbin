# What an app sends to show its store account holds a subscription, and the
# answers when the proof is bad or the subscription is another account's.
module Api
  module V3
    module StoreSubscriptionProof
      extend ActiveSupport::Concern

      included do
        before_action -> { doorkeeper_authorize! :account }
        rescue_from StoreSubscription::Claim::Invalid, with: :render_invalid_proof
        rescue_from StoreSubscription::OwnedByAnotherAccount, with: :render_owned_by_another_account
      end

      private

      def proof_params
        store = required_string("store")
        raise invalid("store", "invalid_value", "Store must be apple.") unless store == "apple"
        {signed_transaction: required_string("signed_transaction")}
      end

      # A lapsed account must be able to buy its way back.
      def lapsed_account_allowed?
        true
      end

      def render_invalid_proof(error)
        render_problem :unprocessable_content, "validation_failed",
          title: "Validation failed",
          detail: error.message,
          errors: [{pointer: "/signed_transaction", code: "invalid_value", detail: error.message}]
      end

      # Names the other account only as far as its owner would recognise it.
      def render_owned_by_another_account(error)
        subscription = error.subscription
        render_problem :conflict, "store_subscription_owned",
          title: "Subscription belongs to another account",
          detail: "This store account's subscription pays for another Feedbin account.",
          owner: {email_hint: EmailHint.new(subscription.user.email).to_s},
          movable: !subscription.moved_at&.after?(StoreSubscription::MOVE_INTERVAL.ago),
          movable_at: subscription.movable_at&.utc&.iso8601
      end
    end
  end
end
