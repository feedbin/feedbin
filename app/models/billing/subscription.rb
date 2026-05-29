module Billing
  # Modern subscription operations. Replaces Stripe::Subscription.create(plan:)
  # and subscription.plan= with the items/price API. The subscription itself is
  # created at signup (create_trialing); later operations mutate that existing
  # subscription rather than creating new ones.
  class Subscription
    # Used at signup: a trialing, payment-method-less subscription.
    def self.create_trialing(customer_id:, price_id:, trial_end:)
      Stripe::Subscription.create(
        customer: customer_id,
        items: [{price: price_id}],
        trial_end: trial_end.to_i,
        payment_behavior: "default_incomplete",
        trial_settings: {end_behavior: {missing_payment_method: "pause"}},
        expand: ["pending_setup_intent"]
      )
    end

    # Switch the existing subscription's price (used by update_plan / users#update
    # for customers who already have a payment method on file). Keeps a future
    # trial; ends it immediately if the trial has already passed.
    def self.change_price(subscription_id:, price_id:, trial_end:)
      sub = Stripe::Subscription.retrieve(subscription_id)
      params = {
        items: [{id: sub.items.data.first.id, price: price_id}],
        proration_behavior: "none"
      }
      params[:trial_end] = trial_end_param(trial_end) if trial_end
      Stripe::Subscription.update(subscription_id, params)
    end

    def self.trial_end_param(trial_end)
      return "now" if trial_end.nil? || trial_end.past?
      trial_end.to_i
    end
  end
end
