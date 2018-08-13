module Api
  module V2
    class InAppPurchasesController < ApiController
      respond_to :json

      before_action :validate_content_type, only: [:create]
      skip_before_action :valid_user

      def create
        @user = current_user
        receipt_data = params[:in_app_purchase][:receipt_data]
        response = receipt_response(receipt_data, Feedbin::Application.config.iap_endpoint[:production])

        if response["status"] == 21007
          response = receipt_response(receipt_data, Feedbin::Application.config.iap_endpoint[:sandbox])
        end

        if response["status"] == 0
          receipts = response["receipt"]["in_app"]
          receipts.each do |receipt|
            InAppPurchase.create_from_receipt_json(@user, receipt, response)
          end
        else
          Honeybadger.notify(
            error_class: "InAppPurchasesController#create",
            error_message: error_codes[response["status"]] || "Receipt verification failed",
            parameters: {status: response["status"]},
          )
          head :bad_request
        end
      end

      private

      def receipt_response(receipt_data, iap_endpoint)
        body = {"receipt-data" => receipt_data}.to_json

        uri = URI(iap_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request.body = body

        response = http.request(request)

        JSON.parse(response.body)
      end

      def error_codes
        {
          21000 => "The App Store could not read the JSON object you provided.",
          21002 => "The data in the receipt-data property was malformed or missing.",
          21003 => "The receipt could not be authenticated.",
          21004 => "The shared secret you provided does not match the shared secret on file for your account. Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions.",
          21005 => "The receipt server is not currently available.",
          21006 => "This receipt is valid but the subscription has expired. When this status code is returned to your server, the receipt data is also decoded and returned as part of the response. Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions.",
          21007 => "This receipt is from the test environment, but it was sent to the production environment for verification. Send it to the test environment instead.",
          21008 => "This receipt is from the production environment, but it was sent to the test environment for verification. Send it to the production environment instead.",
        }
      end
    end
  end
end
