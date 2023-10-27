module Shared
  module Billing
    class BillingSubscribeView < ApplicationComponent

      def initialize(user:, plans:, default_plan:)
        @user = user
        @plans = plans
        @default_plan = default_plan
        @checkout_id = "checkout"
        @stimulus_controller = :payments
        @expandable_outlet = "#{@stimulus_controller}-expandable"
      end

      def template
        div class: "group", data: stimulus_controller do
          form_for @user do |form|
            render Settings::ControlGroupComponent.new class: "mb-14" do |group|
              group.header do
                "Plan"
              end

              @plans.each do |plan|
                plan_row(plan:, form:, group:)
              end
            end
          end

          render Settings::H2Component.new do
            "Payment Method"
          end

          p class: "group-data-[payments-ready-value=true]:tw-hidden" do
            "Loading…"
          end

          render App::ExpandableContainerComponent.new(selector: @expandable_outlet) do |expandable|
            expandable.content do
              div class: "mb-8", data: stimulus_item(target: :payment_element, for: @stimulus_controller)

              render Settings::ButtonRowComponent.new do
                button class: "button", data: stimulus_item(target: :submit_button, actions: {click: :submit}, for: @stimulus_controller) do
                  "Subscribe"
                end
              end
            end
          end
        end
      end

      def plan_row(plan:, form:, group:)
        group.item do
          form.radio_button(:plan_id, plan.id, {
            id: helpers.dom_id(plan),
            class: "peer",
            checked: plan == @default_plan,
            data: stimulus_item(
              actions: {
                change: :update_amount
              },
              params: {
                amount: plan.price_in_cents,
              },
              for: @stimulus_controller
            )
          })
          label for: helpers.dom_id(plan), class: "group" do
            render Settings::ControlRowComponent.new do |row|
              row.title do
                plain "#{helpers.number_to_currency(plan.price, precision: 0)} / #{plan.period}"
              end
              row.control { render Form::RadioComponent.new }
            end
          end
        end
      end

      def stimulus_controller
        stimulus(
          controller: @stimulus_controller,
          values: {
            submit_url: helpers.settings_payments_path,
            confirmation_url: helpers.subscribe_settings_billing_url,
            stripe_public_key: ENV["STRIPE_PUBLIC_KEY"],
            ready: "false",
            visible: "false",
            default_plan_price: @default_plan.price_in_cents,
            trialing: @user.days_left > 0,
          },
          outlets: {
            expandable: "[data-#{@expandable_outlet}]"
          }
        )
      end
    end
  end
end