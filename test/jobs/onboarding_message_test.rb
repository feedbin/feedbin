require "test_helper"

class OnboardingMessageTest < ActionMailer::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  test "should send onboarding_1_welcome" do
    @user = users(:ann)
    assert_emails 1 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_1_welcome).name.to_s)
    end
  end

  test "should send onboarding_2_mobile" do
    @user = users(:ann)
    assert_emails 1 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_2_mobile).name.to_s)
    end
  end

  test "should not send onboarding_2_mobile" do
    @user = users(:ann)
    @user.update(api_client: "yes")
    assert_emails 0 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_2_mobile).name.to_s)
    end
  end

  test "should send onboarding_3_subscribe" do
    @user = users(:ann)
    assert_emails 1 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_3_subscribe).name.to_s)
    end
  end

  test "should not send onboarding_3_subscribe" do
    @user = users(:ann)
    create_feeds(@user, 10)
    assert_emails 0 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_3_subscribe).name.to_s)
    end
  end

  test "should send onboarding_4_expiring" do
    @user = users(:ann)
    assert_emails 1 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_4_expiring).name.to_s)
    end
  end

  test "should send onboarding_5_expired" do
    Sidekiq::Worker.clear_all
    @user = users(:ann)
    assert_emails 1 do
      OnboardingMessage.new.perform(@user.id, MarketingMailer.method(:onboarding_5_expired).name.to_s)
    end
  end

  test "should skip because it's a paid account" do
    @user = users(:ben)
    assert_emails 0 do
      %i[onboarding_5_expired onboarding_4_expiring onboarding_3_subscribe onboarding_2_mobile onboarding_1_welcome].each do |method|
        OnboardingMessage.new.perform(@user.id, MarketingMailer.method(method).name.to_s)
      end
    end
  end

  test "should skip because unsubscribed" do
    @user = users(:ann)
    @user.update(marketing_unsubscribe: "1")
    assert_emails 0 do
      %i[onboarding_5_expired onboarding_4_expiring onboarding_3_subscribe onboarding_2_mobile onboarding_1_welcome].each do |method|
        OnboardingMessage.new.perform(@user.id, MarketingMailer.method(method).name.to_s)
      end
    end
  end
end
