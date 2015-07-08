module Api
  module V2
    class InAppPurchasesController < ApiController

      respond_to :json

      before_action :validate_content_type, only: [:create]

      def create
        @user = current_user
        response = receipt_response(params[:in_app_purchase][:receipt_data])
        if response["status"] == 0
          receipts = response["receipt"]["in_app"]
          receipts.each do |receipt|
            result = InAppPurchase.create_from_receipt_json(@user, receipt)
          end
        else
          render nothing: true, status: :bad_request
        end
      end

      private

      def receipt_response(receipt_data)
        body = {'receipt-data' => receipt_data}.to_json

        uri = URI(Feedbin::Application.config.iap_endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Accept'] = "application/json"
        request['Content-Type'] = "application/json"
        request.body = body

        response = http.request(request)

        JSON.parse(response.body)
      end

    end
  end
end
