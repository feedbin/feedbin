require "test_helper"

class MarketingMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:new)
  end

  def assert_marketing_email(mail, subject:)
    assert_equal [@user.email], mail.to
    assert_equal ["example@example.com"], mail.from
    assert_equal subject, mail.subject
  end

  test "onboarding_1_welcome is addressed to the user with the welcome subject" do
    mail = MarketingMailer.onboarding_1_welcome(@user)
    assert_marketing_email mail, subject: "Welcome to Feedbin - a beautiful place to read on the web"
  end

  test "onboarding_2_mobile uses the mobile subject" do
    mail = MarketingMailer.onboarding_2_mobile(@user)
    assert_marketing_email mail, subject: "Own your news feed and read on the go with Feedbin"
  end

  test "onboarding_3_subscribe uses the subscribe subject" do
    mail = MarketingMailer.onboarding_3_subscribe(@user)
    assert_marketing_email mail, subject: "Follow your passions with Feedbin "
  end

  test "onboarding_4_expiring uses the expiring subject" do
    mail = MarketingMailer.onboarding_4_expiring(@user)
    assert_marketing_email mail, subject: "Your Feedbin trial expires tomorrow - keep your account today!"
  end

  test "onboarding_5_expired looks up the user by id" do
    mail = MarketingMailer.onboarding_5_expired(@user.id)
    assert_marketing_email mail, subject: "Your Feedbin trial has expired"
  end

  test "member_discount uses the discount subject" do
    mail = MarketingMailer.member_discount(@user)
    assert_marketing_email mail, subject: "Own your news feed with Feedbin - Discount for members"
  end
end
