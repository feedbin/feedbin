class Settings::BillingsController < ApplicationController

  before_action :plan_exists, only: [:update_plan]

  def index
    @user = current_user

    payments
    plan_setup

    render layout: "settings"
  end

  def edit
    @user = current_user
    @default_plan = @user.plan
    plan_setup

    render layout: "settings"
  end

  def payment_history
    payments
    render layout: "settings"
  end

  def update_plan
    @user = current_user
    plan = Plan.find(params[:plan])
    @user.plan = plan
    if @user.save
      redirect_to settings_billing_url, notice: "Plan successfully changed."
    else
      redirect_to settings_billing_url, alert: @user.errors.full_messages.to_sentence.presence || "There was a problem changing your plan."
    end
  rescue Stripe::CardError
    redirect_to settings_billing_url, alert: "Your card was declined, please update your billing information."
  end

  def create_subscription
    @user = current_user
    plan = Plan.find(params[:plan_id])

    unless @user.available_plans.include?(plan)
      return render json: {error: "That plan isn't available on your account."}, status: :unprocessable_entity
    end

    subscription = @user.stripe_customer.subscription
    unless subscription
      return render json: {error: "No active subscription found. Please contact support."}, status: :unprocessable_entity
    end

    intent =
      if params[:intent_id].present?
        Billing::Subscription.finalize(
          customer_id: @user.customer_id, subscription_id: subscription.id,
          price_id: plan.stripe_id, trial_end: @user.trial_end, intent_id: params[:intent_id]
        )
      else
        Billing::Subscription.subscribe(
          customer_id: @user.customer_id, subscription_id: subscription.id,
          price_id: plan.stripe_id, trial_end: @user.trial_end, confirmation_token: params[:confirmation_token]
        )
      end

    if intent.status == "succeeded"
      # Persist the plan without re-triggering the price change in update_billing
      # (Billing::Subscription.subscribe already changed the Stripe side).
      @user.skip_billing_plan_change = true
      @user.update(plan: plan)
      Rails.cache.delete(FeedbinUtils.payment_details_key(@user.id))
      render json: {status: intent.status}
    else
      render json: {status: intent.status, client_secret: intent.client_secret, requires_action: true}
    end
  rescue Stripe::StripeError => exception
    render json: {error: exception.message}, status: :unprocessable_entity
  end

  def payment_details
    @message = Rails.cache.fetch(FeedbinUtils.payment_details_key(current_user.id), expires_in: 5.minutes) {
      Billing::PaymentMethod.summary(current_user.customer_id)
    }
  rescue
    @message = "No payment info"
  end

  def update_credit_card
    @user = current_user

    if params[:intent_id].blank? && params[:confirmation_token].blank?
      Librato.increment("billing.token_missing")
      return render json: {error: "There was a problem updating your card. Please try again."}, status: :unprocessable_entity
    end

    intent =
      if params[:intent_id].present?
        Billing::PaymentMethod.finalize(customer_id: @user.customer_id, intent_id: params[:intent_id])
      else
        Billing::PaymentMethod.confirm_and_set_default(
          customer_id: @user.customer_id, confirmation_token: params[:confirmation_token]
        )
      end

    if intent.status == "succeeded"
      Rails.cache.delete(FeedbinUtils.payment_details_key(@user.id))
      @user.reactivate_billing!
      render json: {status: intent.status}
    else
      render json: {status: intent.status, client_secret: intent.client_secret, requires_action: true}
    end
  rescue Stripe::StripeError => exception
    render json: {error: exception.message}, status: :unprocessable_entity
  end

  private

  def payments
    @default_plan = Plan.where(price_tier: @user.price_tier, stripe_id: ["basic-yearly", "basic-yearly-2", "basic-yearly-3"]).first

    @next_payment = @user.billing_events.where(event_type: "invoice.payment_succeeded")
    @next_payment = @next_payment.to_a.sort_by { |next_payment| -next_payment.event_object["created"].to_i }
    if @next_payment.present? && !@user.timed_plan? && !@user.app_plan?
      @next_payment.first.event_object["lines"]["data"].each do |line|
        if line.safe_dig("parent", "type") == "subscription_item_details"
          @next_payment_date = Time.at(line["period"]["end"]).utc.to_datetime
        end
      end
    end

    stripe_purchases = @user.billing_events.where(event_type: "charge.succeeded")
    in_app_purchases = @user.in_app_purchases
    in_app_subscriptions = @user.app_store_notifications.where(notification_type: ["SUBSCRIBED", "DID_RENEW"])
    all_purchases = (stripe_purchases.to_a + in_app_purchases.to_a + in_app_subscriptions.to_a)
    @billing_events = all_purchases.sort_by { |billing_event| billing_event.purchase_date }.reverse
  end

  def plan_setup
    @plans = @user.available_plans
    @plan_data = @plans.map { |plan|
      {id: plan.id, name: plan.name, amount: plan.price_in_cents}
    }
  end

  def plan_exists
    render_404 unless Plan.exists?(params[:plan].to_i)
  end

end
