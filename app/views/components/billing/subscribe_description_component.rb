module Billing
  class SubscribeDescriptionComponent < ApplicationComponent
    register_value_helper :number_to_currency

    # Each plan's note shows only when the billing controller's selectedPlan
    # value (the chosen plan's index) matches. These are written as literals so
    # Tailwind's content scan generates the variants — it can't see interpolated
    # class names. Indexed by the plan's position in the list.
    PLAN_VISIBILITY = [
      "group-data-[billing-selected-plan-value=0]:block",
      "group-data-[billing-selected-plan-value=1]:block",
      "group-data-[billing-selected-plan-value=2]:block",
      "group-data-[billing-selected-plan-value=3]:block",
      "group-data-[billing-selected-plan-value=4]:block",
      "group-data-[billing-selected-plan-value=5]:block",
      "group-data-[billing-selected-plan-value=6]:block",
      "group-data-[billing-selected-plan-value=7]:block"
    ].freeze

    def initialize(user:, plans:, default_plan:)
      @user = user
      @plans = plans
      @default_plan = default_plan
    end

    def view_template
      div(class: "text-500 text-sm mt-4 tw-hidden group-data-[billing-mounted-value=true]:block") do
        @plans.each_with_index { |plan, index| description_for(plan, index) }
      end
    end

    private

    def description_for(plan, index)
      p(class: "tw-hidden #{PLAN_VISIBILITY[index]}") do
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
