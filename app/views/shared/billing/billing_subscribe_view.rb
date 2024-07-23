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

      def view_template
        p class: "mb-8" do
          if @user.plan.stripe_id == "trial"
            if @user.days_left <= 0
              "Your trial has ended. Subscribe now to continue using Feedbin."
            else
              plain "Your trial period will end in "
              strong { helpers.pluralize(@user.days_left, 'day') }
              plain ". Subscribe now to continue using Feedbin uninterrupted."
            end
          end
        end

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
              div class: "mb-4", data: stimulus_item(target: :payment_element, for: @stimulus_controller)

              payment_info

              render Settings::ButtonRowComponent.new do
                button data: submit_data, class: "button group-data-[payments-payment-method-value=apple-pay]:tw-hidden"  do
                  "Subscribe"
                end

                button data: submit_data, class: "tw-hidden group-data-[payments-payment-method-value=apple-pay]:inline-block [-webkit-appearance:-apple-pay-button] [-apple-pay-button-type:subscribe] [-apple-pay-button-style:var(--apple-pay-button-style)]"
              end

            end
          end
        end
      end

      def payment_info
        @plans.each do |plan|
          p class: "text-sm text-500 #{plan.period == "year" ? "group-data-[payments-plan-period-value=month]:tw-hidden" : "group-data-[payments-plan-period-value=year]:tw-hidden"}" do
            plain "Subscribing will charge you "
            strong { helpers.number_to_currency(plan.price, precision: 0) }

            if @user.trial_end.future?
              plain " on "
              strong { @user.trial_end.to_formatted_s(:date) }
            else
              plain " immediately"
            end

            plain " and again each #{plan.period} thereafter. Full refunds are available at any time, no questions asked."
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
                change: :update_plan
              },
              params: {
                amount: plan.price_in_cents,
                period: plan.period
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

      def submit_data
        stimulus_item(target: :submit_button, actions: {click: :submit}, for: @stimulus_controller)
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
            trialing: (@user.days_left > 0).to_s,
            payment_method: nil,
            plan_period: @default_plan.period
          },
          outlets: {
            expandable: "[data-#{@expandable_outlet}]"
          }
        )
      end
    end
  end
end