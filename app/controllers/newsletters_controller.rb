class NewslettersController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    newsletter = Newsletter.new(params)
    user = User.where(newsletter_token: newsletter.token).take
    if newsletter.valid?
      NewsletterEntry.create(newsletter, user)
    end
    head :ok
  end

end
