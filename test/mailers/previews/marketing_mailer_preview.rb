# Preview all emails at http://localhost:3000/rails/mailers/marketing_mailer
class MarketingMailerPreview < ActionMailer::Preview
  def member_discount
    MarketingMailer.member_discount(User.first)
  end
end
