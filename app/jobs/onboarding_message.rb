class OnboardingMessage
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(user_id, message)
    @user = User.find(user_id)
    @message = message.to_sym
    self.send(@message)
  rescue ActiveRecord::RecordNotFound
  end

  private

  def onboarding_1_welcome
    if @user.trialing?
      send_message
    end
  end

  def onboarding_2_mobile
    if @user.trialing? && @user.api_client.blank?
      send_message
    end
  end

  def onboarding_3_subscribe
    if @user.trialing? && @user.subscriptions.count < 10
      send_message
    end
  end

  def onboarding_4_expiring
    if @user.trialing?
      send_message
    end
  end

  def onboarding_5_expired
    if @user.trialing?
      MarketingMailer.delay_for(1.day).send(@message, @user.id)
    end
  end

  def send_message
    MarketingMailer.send(@message, @user).deliver
  end



end