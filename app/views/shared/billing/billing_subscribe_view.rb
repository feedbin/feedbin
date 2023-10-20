module Shared
  module Billing
    class BillingSubscribeView < ApplicationComponent

      def initialize
        @checkout_id = "checkout"
      end

      def template
        div data: stimulus_controller do
          "hello"
        end

        div class: "w-[412px]", id: @checkout_id
      end

      def stimulus_controller
        stimulus(
          controller: :payments,
          values: {
            url: helpers.checkout_session_settings_billing_path,
            checkout_id: @checkout_id,
            stripe_public_key: ENV["STRIPE_PUBLIC_KEY"]
          }
        )
      end
    end
  end
end