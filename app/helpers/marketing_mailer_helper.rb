module MarketingMailerHelper
  def unsubscribe_link(user)
    id = Rails.application.message_verifier(:unsubscribe).generate(user.id)
    email_unsubscribe_public_setting_url(id)
  end
end
