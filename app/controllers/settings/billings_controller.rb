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
    @user.save
    redirect_to settings_billing_url, notice: "Plan successfully changed."
  rescue Stripe::CardError
    redirect_to settings_billing_url, alert: "Your card was declined, please update your billing information."
  end

  def payment_details
    @message = Rails.cache.fetch(FeedbinUtils.payment_details_key(current_user.id), expires_in: 5.minutes) {
      customer = Customer.retrieve(@user.customer_id)
      card = customer.sources.first
      "#{card.brand} ××#{card.last4[-2..-1]}"
    }
  rescue
    @message = "No payment info"
  end

  def update_credit_card
    @user = current_user

    if params[:stripe_token].present?
      @user.stripe_token = params[:stripe_token]
      if @user.save
        Rails.cache.delete(FeedbinUtils.payment_details_key(current_user.id))
        customer = Customer.retrieve(@user.customer_id)
        customer.reopen_account if customer.unpaid?
        redirect_to settings_billing_url, notice: "Your card has been updated."
      else
        redirect_to edit_settings_billing_url, alert: @user.errors.messages[:base].join(" ")
      end
    else
      redirect_to edit_settings_billing_url, alert: "There was a problem updating your card. Please try again."
      Honeybadger.increment_counter("billing.token_missing")
    end
  rescue Stripe::CardError => exception
    redirect_to edit_settings_billing_url, alert: exception.message
  end

  private

  def payments
    @default_plan = Plan.where(price_tier: @user.price_tier, stripe_id: ["basic-yearly", "basic-yearly-2", "basic-yearly-3"]).first

    @next_payment = @user.billing_events.where(event_type: "invoice.payment_succeeded")
    @next_payment = @next_payment.to_a.sort_by { |next_payment| -next_payment.event_object["date"] }
    if @next_payment.present? && !@user.timed_plan? && !@user.app_plan?
      @next_payment.first.event_object["lines"]["data"].each do |event|
        if event.safe_dig("type") == "subscription"
          @next_payment_date = Time.at(event["period"]["end"]).utc.to_datetime
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
