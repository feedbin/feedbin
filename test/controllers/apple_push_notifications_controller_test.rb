require "test_helper"

class ApplePushNotificationsControllerTest < ActionController::TestCase
  def setup
    @user = users(:ben)
    @token = ActionsController.new.send(:authentication_token, @user)
    ENV["APPLE_PUSH_CERT"] = create_cert("/tmp/p12.p12")
  end

  test "should create push package" do
    raw_post :create, default_params, {authentication_token: @token}.to_json
    assert_response :success
    assert_equal response.header["Content-Type"], "application/zip"
    assert_equal @user, assigns(:user)
  end

  test "should not create push package with invalid token" do
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      raw_post :create, default_params, {authentication_token: "#{@token}s"}.to_json
    end
  end

  test "should destroy device token" do
    set_authorization_header
    patch :update, params: default_params.merge(device_token: "token")
    assert_difference("Device.count", -1) do
      delete :delete, params: default_params.merge(device_token: "token")
    end
    assert_response :success
  end

  test "should update device token" do
    set_authorization_header
    assert_difference("Device.count") do
      patch :update, params: default_params.merge(device_token: "token")
    end
    assert_response :success
  end

  private

  def default_params
    {version: 1, website_push_id: ENV["APPLE_PUSH_WEBSITE_ID"]}
  end

  def set_authorization_header
    @request.headers["Authorization"] = "ApplePushNotifications #{@token}"
  end

  def create_cert(path)
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.not_before = Time.new
    cert.not_after = cert.not_before + 10_000
    cert.public_key = rsa_key.public_key
    cert.sign rsa_key, OpenSSL::Digest::SHA1.new
    p12 = OpenSSL::PKCS12.create(nil, nil, rsa_key, cert)
    File.open(path, "wb") { |file| file.write p12.to_der }
    path
  end
end
