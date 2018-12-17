class MarketingMailer < ApplicationMailer
  default from: ENV["FROM_ADDRESS_MARKETING"]

  layout "marketing_mailer"

  def onboarding_1_welcome(user)
    @user = user
    mail(to: user.email, subject: "Welcome to Feedbin - a beautiful place to read on the web")
  end

  def onboarding_2_mobile(user)
    @user = user
    mail(to: user.email, subject: "Own your news feed and read on the go with Feedbin")
  end

  def onboarding_3_subscribe(user)
    @user = user
    mail(to: user.email, subject: "Follow your passions with Feedbin ")
  end

  def onboarding_4_expiring(user)
    @user = user
    mail(to: user.email, subject: "Your Feedbin trial expires tomorrow - keep your account today!")
  end

  def onboarding_5_expired(user)
    @user = User.find(user)
    mail(to: @user.email, subject: "Your Feedbin trial has expired")
  end

  def member_discount(user)
    @user = user
    mail(to: user.email, subject: "Own your news feed with Feedbin - Discount for members")
  end
end
