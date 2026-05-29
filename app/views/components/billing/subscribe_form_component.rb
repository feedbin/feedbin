module Billing
  class SubscribeFormComponent < ApplicationComponent
    include Phlex::Rails::Helpers::Routes
    register_value_helper :number_to_currency

    def initialize(publishable_key:, plans:, default_plan:, subscribe_title:, mode:)
      @publishable_key = publishable_key
      @plans = plans
      @default_plan = default_plan
      @subscribe_title = subscribe_title
      @mode = mode # "setup" for a future trial, "payment" for an immediate charge
    end

    def view_template
      render Billing::PaymentElementComponent.new(
        publishable_key: @publishable_key,
        mode: @mode,
        amount: @mode == "payment" ? @default_plan.price_in_cents : 0,
        currency: "usd",
        endpoint: create_subscription_settings_billing_path,
        return_url: settings_billing_url,
        submit_label: "Subscribe",
        default_plan_id: @default_plan.id
      ) do
        render Settings::ControlGroupComponent.new(class: "mb-14") do |group|
          group.header { @subscribe_title }
          @plans.each { |plan| render_plan_row(group, plan) }
        end
      end
    end

    private

    def render_plan_row(group, plan)
      group.item do
        input(
          type: "radio", name: "plan_id", id: dom_id(plan), value: plan.id,
          class: "peer", checked: plan == @default_plan,
          data: stimulus_item(target: :plan_input, actions: {change: :plan_changed}, for: :billing).merge(amount: plan.price_in_cents)
        )
        label(for: dom_id(plan), class: "group") do
          render Settings::ControlRowComponent.new do |row|
            row.title { "#{number_to_currency(plan.price, precision: 0)}/#{plan.period}" }
            row.control { render Form::RadioComponent.new }
          end
        end
      end
    end
  end
end
