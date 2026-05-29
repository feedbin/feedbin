module Billing
  class SubscribeDescriptionComponent < ApplicationComponent
    register_value_helper :number_to_currency

    def initialize(user:, plans:, default_plan:)
      @user = user
      @plans = plans
      @default_plan = default_plan
    end

    def view_template
      div(class: "subscribe-description mt-4") do
        @plans.each { |plan| description_for(plan) }
      end
    end

    private

    def description_for(plan)
      p(
        class: ("hidden" unless plan == @default_plan),
        data: stimulus_item(target: :plan_help, for: :billing).merge(plan_id: plan.id)
      ) do
        plain "Subscribing will charge your card "
        strong { number_to_currency(plan.price, precision: 0) }
        if @user.trial_end.future?
          plain " when your #{plan_name} ends on "
          strong { @user.trial_end.to_formatted_s(:date) }
          plain " and again each #{plan.period} thereafter. Full refunds are available at any time, no questions asked."
        else
          plain " immediately and again each #{plan.period} thereafter. Full refunds are available at any time, no questions asked."
        end
      end
    end

    def plan_name
      @user.plan.stripe_id == "timed" ? "prepaid plan" : "trial"
    end
  end
end
