require "test_helper"

class AuthenticationTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
  end

  test "generates a hex token for non-newsletter purposes" do
    token = @user.authentication_tokens.create!(purpose: :cookies, length: 16)
    assert_match(/\A[0-9a-f]{32}\z/, token.token)
  end

  test "generates an alpha token for newsletter purposes" do
    token = @user.authentication_tokens.create!(purpose: :newsletters)
    assert_match(/\A[a-z]{5}\z/, token.token)
  end

  test "skips generation when token is already set" do
    token = @user.authentication_tokens.create!(purpose: :cookies, token: "preset-token")
    assert_equal "preset-token", token.token
  end

  test "skips generation when skip_generate is set" do
    token = @user.authentication_tokens.new(purpose: :cookies, skip_generate: true, token: "raw")
    token.save!
    assert_equal "raw", token.token
  end

  test "active scope returns only active tokens" do
    active = @user.authentication_tokens.create!(purpose: :cookies, length: 16)
    inactive = @user.authentication_tokens.create!(purpose: :cookies, length: 16)
    inactive.update_column(:active, false)

    assert_includes AuthenticationToken.active, active
    refute_includes AuthenticationToken.active, inactive
  end

  test "title combines token with NEWSLETTER_ADDRESS_HOST" do
    ENV["NEWSLETTER_ADDRESS_HOST"] = "newsletters.example.com"
    begin
      token = @user.authentication_tokens.create!(purpose: :newsletters)
      assert_equal "#{token.token}@newsletters.example.com", token.title
    ensure
      ENV.delete("NEWSLETTER_ADDRESS_HOST")
    end
  end

  test "generate_alpha_token returns a 5-letter token" do
    assert_match(/\A[a-z]{5}\z/, AuthenticationToken.generate_alpha_token)
  end

  test "generate_custom_token returns a token with the given prefix" do
    token = AuthenticationToken.generate_custom_token("hello")
    assert_match(/\Ahello\.\d{3}\z/, token)
  end

  test "description and newsletter_tag are stored in data" do
    token = @user.authentication_tokens.create!(purpose: :newsletters, description: "test", newsletter_tag: "news")
    assert_equal "test", token.description
    assert_equal "news", token.newsletter_tag
  end
end
