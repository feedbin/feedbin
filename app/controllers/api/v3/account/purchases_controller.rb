module Api
  module V3
    module Account
      class PurchasesController < ApiController
        before_action -> { require_scope("account") }

        def create
          receipt = AppStoreReceipt.verify(required_string("receipt_data"))
          return render_refused(receipt["status"]) unless receipt["status"] == 0

          Array(receipt.dig("receipt", "in_app")).each { InAppPurchase.create_from_receipt_json(@user, _1, receipt) }
          render json: AccountSerializer.new(@user.reload).to_h
        end

        private

        # A suspended account must be able to buy its way back.
        def lapsed_account_allowed?
          true
        end

        def render_refused(status)
          render_problem :unprocessable_content, "validation_failed",
            title: "Validation failed",
            detail: "Apple did not verify the receipt: status #{status}.",
            errors: [{pointer: "/receipt_data", code: "invalid_value", detail: "Apple returned status #{status}."}]
        end
      end
    end
  end
end
