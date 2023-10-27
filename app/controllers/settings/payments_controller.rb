class Settings::PaymentsController < ApplicationController

  def create
    @user = current_user

    subscription = @user.stripe_customer.subscription

    updated_subscription = Stripe::Subscription.update(
      subscription.id,
      cancel_at_period_end: false,
      payment_behavior: "default_incomplete",
      payment_settings: {save_default_payment_method: "on_subscription"},
      expand: ["latest_invoice.payment_intent", "pending_setup_intent"],
      items: [
        { id: subscription.items.data[0].id, price: 'basic-monthly-3' }
      ]
    )

    if updated_subscription.pending_setup_intent.present?
      render json: { type: "setup", clientSecret: updated_subscription.pending_setup_intent.client_secret }
    else
      render json: { type: "payment", clientSecret: updated_subscription.latest_invoice.payment_intent.client_secret }.to_json
    end
  end

end
