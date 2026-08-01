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
    plan_setup

    # The wallet button quotes an amount, so the default has to be one of the plans
    # the page actually rendered. `available_plans` filters by the user's price tier
    # and leaves out trial, free and prepaid plans, so a customer on one of those has
    # a current plan that isn't in the list — and handing its id to Stripe.js left it
    # without a paymentRequest to quote.
    @default_plan = @plans.detect { |plan| plan == @user.plan } || @plans.first

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

  # Confirmed client-side, which is what triggers 3D Secure when the card needs
  # it. The card details never reach us — the form posts back only the resulting
  # PaymentMethod id.
  def create_setup_intent
    intent = Stripe::SetupIntent.create(
      {customer: current_user.customer_id, usage: "off_session"},
      {stripe_version: STRIPE_INTENTS_API_VERSION}
    )
    render json: {client_secret: intent.client_secret}
  rescue Stripe::StripeError => exception
    ErrorService.notify(exception)
    render json: {error: "Could not start card setup. Please try again."}, status: :service_unavailable
  end

  # Where the invoice.payment_action_required email lands. The client secret is
  # looked up fresh rather than carried in the link, so the URL is safe to email
  # and still works if Stripe retries the charge before the customer clicks.
  def authenticate
    customer = Customer.retrieve(@user.customer_id)
    @client_secret = customer.authentication_client_secret

    if @client_secret
      render layout: "settings"
    elsif customer.open_invoice?
      # A declined or abandoned challenge leaves the PaymentIntent needing a payment
      # method rather than an authentication, so there's nothing left to confirm —
      # but the invoice is still owed. Saying "no payment waiting" and dropping them
      # on the billing page would read as though it had gone through.
      redirect_to edit_settings_billing_url, alert: "That payment could not be confirmed. Please update your card to complete it."
    else
      redirect_to settings_billing_url, notice: "There's no payment waiting to be confirmed."
    end
  rescue Stripe::StripeError => exception
    ErrorService.notify(exception)
    redirect_to settings_billing_url, alert: "Could not load the payment. Please try again."
  end

  def payment_details
    @message = Rails.cache.fetch(FeedbinUtils.payment_details_key(current_user.id), expires_in: 5.minutes) {
      Customer.retrieve(@user.customer_id).card_description
    }
  rescue
    @message = "No payment info"
  end

  def update_credit_card
    @user = current_user
    was_suspended = @user.suspended

    if params[:stripe_token].present?
      @user.stripe_token = params[:stripe_token]
      if @user.save
        Rails.cache.delete(FeedbinUtils.payment_details_key(current_user.id))
        customer = Customer.retrieve(@user.customer_id)
        recovery = customer.reopen_account if customer.unpaid?

        # A card update is often the answer to a failed charge, so collect what's
        # owed with the new card. Skipped after a re-anchor, which already wrote
        # the lapsed period off — collecting it too would double charge.
        if recovery != :reanchored && customer.pay_open_invoice == :requires_action
          # Nothing has been paid yet, so a suspension stays until the customer
          # authenticates — abandoning the challenge must not buy access. The
          # subscription_reactivated? webhook lifts it once the payment lands.
          @user.deactivate if was_suspended
          redirect_to authenticate_settings_billing_url
        else
          redirect_to settings_billing_url, notice: "Your card has been updated."
        end
      else
        redirect_to edit_settings_billing_url, alert: @user.errors.messages[:base].join(" ")
      end
    else
      redirect_to edit_settings_billing_url, alert: "There was a problem updating your card. Please try again."
      Librato.increment("billing.token_missing")
    end
  rescue Stripe::CardError => exception
    # Saving the card lifted the suspension before we knew the card worked. Put it
    # back, because nothing downstream will: Stripe rolls a declined re-anchor
    # back completely, and it never reattempts payment on an unpaid subscription,
    # so no further webhook arrives to suspend the account again.
    @user.deactivate if was_suspended
    redirect_to edit_settings_billing_url, alert: exception.message
  rescue Stripe::StripeError => exception
    # Anything else — a collection race, a Stripe outage — happened after the
    # card saved, so report the save honestly and leave the invoice for a retry.
    # The suspension logic is the same as above: no webhook will re-suspend.
    ErrorService.notify(exception)
    @user.deactivate if was_suspended
    redirect_to settings_billing_url, alert: "Your card has been updated, but we could not collect the open invoice. Please try again."
  end

  private

  def payments
    @default_plan = Plan.where(price_tier: @user.price_tier, stripe_id: ["basic-yearly", "basic-yearly-2", "basic-yearly-3", "basic-yearly-4"]).first

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
