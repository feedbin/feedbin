module Api
  module V3
    # GET, PATCH and DELETE /account, and POST /account/purchases.
    class AccountController < ApiController
      def show
        render json: AccountSerializer.new(@user).to_h
      end

      # A merge patch over settings. Anything else in the body (email,
      # password) is ignored: those change in the web app.
      def update
        settings = request.request_parameters["settings"]
        if settings
          raise Problems::InvalidParameter.new("settings must be an object.", pointer: "/settings", code: "invalid_value") unless settings.is_a?(Hash)
          stored = @user.settings.dup
          settings.slice(*AccountSerializer::SETTINGS.keys).each do |name, value|
            key, type = AccountSerializer::SETTINGS.fetch(name)
            stored[key] = case type
            when :sort
              AccountSerializer::SORTS.fetch(value) { raise Problems::InvalidParameter.new("#{name} must be one of #{AccountSerializer::SORTS.keys.join(", ")}.", pointer: "/settings/#{name}", code: "invalid_value") }
            when :integer
              raise Problems::InvalidParameter.new("#{name} must be a positive integer.", pointer: "/settings/#{name}", code: "invalid_value") unless value.is_a?(Integer) && value.positive?
              value.to_s
            when :boolean
              raise Problems::InvalidParameter.new("#{name} must be true or false.", pointer: "/settings/#{name}", code: "invalid_value") unless [true, false].include?(value)
              value ? "1" : "0"
            end
          end
          @user.update!(settings: stored)
        end
        render json: AccountSerializer.new(@user).to_h
      end

      # Deletion runs in the background, as the web app's does (it mails an
      # OPML export first). The token that asked is revoked now.
      def destroy
        UserDeleter.perform_async(@user.id)
        @token.revoke
        head :no_content
      end

      # Verifies an App Store receipt with Apple (production, then sandbox on
      # 21007) and records each purchase, which extends the plan.
      def purchases
        receipt_data = request.request_parameters["receipt_data"]
        raise Problems::InvalidParameter.new("receipt_data is required.", pointer: "/receipt_data", code: "missing") unless receipt_data.is_a?(String) && receipt_data.present?

        result = AppStoreReceipt.verify(receipt_data)
        unless result["status"] == 0
          return render_problem :unprocessable_content, "validation_failed",
            title: "Validation failed",
            detail: "Apple did not verify the receipt: status #{result["status"]}.",
            errors: [{pointer: "/receipt_data", code: "invalid_value", detail: "Apple returned status #{result["status"]}."}]
        end
        Array(result.dig("receipt", "in_app")).each { InAppPurchase.create_from_receipt_json(@user, _1, result) }
        render json: AccountSerializer.new(@user.reload).to_h
      end
    end
  end
end
