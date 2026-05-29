module Billing
  class PaymentElementComponent < ApplicationComponent
    def initialize(publishable_key:, mode:, amount:, currency:, endpoint:, return_url:, submit_label:, default_plan_id: nil, description: nil)
      @publishable_key = publishable_key
      @mode = mode
      @amount = amount
      @currency = currency
      @endpoint = endpoint
      @return_url = return_url
      @submit_label = submit_label
      @default_plan_id = default_plan_id
      @description = description
    end

    def view_template(&block)
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
        form(data: stimulus_item(actions: {submit: :submit}, for: :billing)) do
          yield if block_given?
          div(id: "payment-element", class: "mb-4", data: stimulus_item(target: :payment_element, for: :billing))
          div(class: "text-red-600 mt-2 hidden", data: stimulus_item(target: :error, for: :billing))
          render(@description) if @description
          render Settings::ButtonRowComponent.new do
            button(type: "submit", class: "button", data: stimulus_item(target: :submit, for: :billing)) { @submit_label }
          end
        end
      end
    end
  end
end
