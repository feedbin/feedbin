require "test_helper"

class Api::V2::InAppPurchasesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:timed)
  end

  test "should create in_app_purchase" do
    api_content_type
    login_as @user
    product_id, product_options = Feedbin::Application.config.iap.to_a.sample

    receipt = {
      transaction_id: SecureRandom.hex,
      purchase_date_ms: Time.now.to_i * 1_000,
      product_id: product_id,
    }
    response = {
      status: 0,
      receipt: {
        in_app: [receipt],
      },
    }
    stub_request(:post, Feedbin::Application.config.iap_endpoint[:production]).
      to_return(body: response.to_json, status: 200)

    time = Time.now
    assert_difference "InAppPurchase.count", +1 do
      Time.stub :now, time do
        post :create, params: {in_app_purchase: {id: nil}}, format: :json
      end
      assert_response :success
    end
    assert_equal((time + product_options[:time]).iso8601, @user.reload.expires_at.iso8601)
  end
end
