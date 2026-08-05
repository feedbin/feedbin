require "test_helper"
require "base64"

class JwsVerifierTest < ActiveSupport::TestCase
  test "rejects a token whose header carries no x5c chain" do
    assert_equal false, JwsVerifier.valid?(token(alg: "ES256"))
  end

  test "rejects a token whose x5c is not a list of certificates" do
    assert_equal false, JwsVerifier.valid?(token(alg: "ES256", x5c: "not-a-list"))
  end

  test "rejects a token whose x5c holds something that is not a certificate" do
    assert_equal false, JwsVerifier.valid?(token(alg: "ES256", x5c: [Base64.strict_encode64("nonsense")]))
  end

  test "rejects a token that is not a token at all" do
    assert_equal false, JwsVerifier.valid?("asdf")
  end

  test "rejects a chain of one certificate rather than passing it vacuously" do
    root = File.read(File.join(Rails.root, "config", "AppleRootCA-G3.cer"))
    single = Base64.strict_encode64(OpenSSL::X509::Certificate.new(root).to_der)

    assert_equal false, JwsVerifier.valid?(token(alg: "ES256", x5c: [single])),
      "a one-certificate chain satisfies each_cons(2) with nothing to check"
  end

  private

  def token(header)
    [
      Base64.urlsafe_encode64(header.to_json, padding: false),
      Base64.urlsafe_encode64({}.to_json, padding: false),
      "signature"
    ].join(".")
  end
end
