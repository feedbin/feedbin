class MarketingMailer < ApplicationMailer

  default from: ENV['FROM_ADDRESS_MARKETING']

  def member_discount(user)
    @user = user
    mail(to: @user.email, subject: 'Own your news feed with Feedbin - Discount for members')
  end

end
