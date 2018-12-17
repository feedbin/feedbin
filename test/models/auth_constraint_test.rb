require "test_helper"

class AuthConstraintTest < ActiveSupport::TestCase
  test "should allow existing admins" do
    user = users(:ben)
    request = request_mock(user.auth_token)
    assert AuthConstraint.admin?(request)
  end

  test "should not allow non-admins" do
    user = users(:new)
    request = request_mock(user.auth_token)
    assert_not AuthConstraint.admin?(request)
  end

  test "should not allow missing users" do
    request = request_mock(SecureRandom.hex)
    assert_not AuthConstraint.admin?(request)
  end

  private

  def request_mock(auth_token)
    cookie_jar = OpenStruct.new(signed: {auth_token: auth_token})
    OpenStruct.new(cookie_jar: cookie_jar)
  end
end
