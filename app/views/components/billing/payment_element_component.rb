module Billing
  class PaymentElementComponent < ApplicationComponent
    def initialize(publishable_key:, mode:, amount:, currency:, endpoint:, return_url:, default_plan_id: nil)
      @publishable_key = publishable_key
      @mode = mode
      @amount = amount
      @currency = currency
      @endpoint = endpoint
      @return_url = return_url
      @default_plan_id = default_plan_id
    end

    def view_template
      div(
        data: stimulus(
          controller: :billing,
          values: {
            publishable_key: @publishable_key,
            mode: @mode,
            amount: @amount,
            currency: @currency,
            endpoint: @endpoint,
            return_url: @return_url,
            default_plan: @default_plan_id
          }
        )
      ) do
        div(id: "payment-element", data: stimulus_item(target: :payment_element, for: :billing))
        div(class: "text-red-600 mt-2 hidden", data: stimulus_item(target: :error, for: :billing))
        yield if block_given?
      end
    end
  end
end
