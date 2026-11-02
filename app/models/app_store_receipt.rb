# Receipt verification against Apple's verifyReceipt service, for the v3
# purchase endpoint (POST /v3/account/purchases). Returns Apple's parsed
# JSON; status 0 is a verified receipt and 21007 means "try the sandbox".
class AppStoreReceipt
  def self.verify(receipt_data)
    endpoints = Feedbin::Application.config.iap_endpoint
    result = post(receipt_data, endpoints[:production])
    result = post(receipt_data, endpoints[:sandbox]) if result["status"] == 21007
    result
  end

  def self.post(receipt_data, endpoint)
    uri = URI(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    # Net::HTTP waits 60 seconds per phase by default, and this runs in a
    # request thread.
    http.open_timeout = 5
    http.write_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    request.body = {"receipt-data" => receipt_data}.to_json
    JSON.parse(http.request(request).body)
  end
end
