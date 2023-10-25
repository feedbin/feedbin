module Shared
  module Billing
    class BillingSubscribeView < ApplicationComponent

      def initialize
        @checkout_id = "checkout"
        @stimulus_controller = :payments
        @expandable_outlet = "#{@stimulus_controller}-expandable"
      end

      def template
        div class: "group", data: stimulus_controller do
          render Settings::H2Component.new do
            "Payment Method"
          end

          p class: "group-data-[payments-ready-value=true]:tw-hidden" do
            "Loading…"
          end

          div data: stimulus_item(target: :payment_container, for: @stimulus_controller) do
            render App::ExpandableContainerComponent.new(selector: @expandable_outlet) do |expandable|
              expandable.content do
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
          },
          outlets: {
            expandable: "[data-#{@expandable_outlet}]"
          }
        )
      end
    end
  end
end