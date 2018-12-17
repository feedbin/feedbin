# Preview all emails at http://localhost:3000/rails/mailers/marketing_mailer
class MarketingMailerPreview < ActionMailer::Preview
  def member_discount
    MarketingMailer.member_discount(User.first)
  end

  def onboarding_1_welcome
    MarketingMailer.onboarding_1_welcome(User.first)
  end

  def onboarding_2_mobile
    MarketingMailer.onboarding_2_mobile(User.first)
  end

  def onboarding_3_subscribe
    MarketingMailer.onboarding_3_subscribe(User.first)
  end

  def onboarding_4_expiring
    MarketingMailer.onboarding_4_expiring(User.first)
  end

  def onboarding_5_expired
    MarketingMailer.onboarding_5_expired(User.first)
  end
end
