module Shared
  module Billing
    class BillingSubscribeView < ApplicationComponent

      def initialize
        @checkout_id = "checkout"
        @stimulus_controller = :payments
      end

      def template
        div class: "group", data: stimulus_controller do
          render Settings::H2Component.new do
            "Payment Method"
          end

          p class: "group-data-[payments-ready-value=true]:tw-hidden" do
            "Loading…"
          end
          div data: stimulus_item(target: :payment_container, for: @stimulus_controller), class: "grid [grid-template-rows:0fr] group-data-[payments-ready-value=true]:[grid-template-rows:1fr] transition-[grid-template-rows] duration-200 overflow-hidden group-data-[payments-visible-value=true]:overflow-visible" do
            div class: "min-h-0 transition transition-[visibility,opacity] opacity-100 group-data-[payments-ready-value=false]:opacity-0 group-data-[payments-ready-value=false]:invisible" do
              div class: "mb-8", id: @checkout_id

              render Settings::ButtonRowComponent.new do
                button class: "button", data: stimulus_item(target: :submit_button, actions: {click: :submit}, for: @stimulus_controller) do
                  "Subscribe"
                end
              end
            end
          end
        end
      end

      def stimulus_controller
        stimulus(
          controller: @stimulus_controller,
          values: {
            submit_url: helpers.subscribe_settings_billing_path,
            confirmation_url: helpers.subscribe_settings_billing_url,
            checkout_id: @checkout_id,
            stripe_public_key: ENV["STRIPE_PUBLIC_KEY"],
            ready: "false",
            visible: "false"
          }
        )
      end
    end
  end
end