module Billing
  class UpdateCardComponent < ApplicationComponent
    include Phlex::Rails::Helpers::Routes

    def initialize(publishable_key:)
      @publishable_key = publishable_key
    end

    def view_template
      render Settings::H1Component.new { "Billing" }
      render Billing::PaymentElementComponent.new(
        publishable_key: @publishable_key,
        mode: "setup",
        amount: 0,
        currency: "usd",
        endpoint: update_credit_card_settings_billing_path,
        return_url: settings_billing_url,
        submit_label: "Update"
      )
    end
  end
end
