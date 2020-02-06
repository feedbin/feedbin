class NewslettersController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    newsletter = Newsletter.new(params)
    user = AuthenticationToken.newsletters.active.where(token: newsletter.token).take&.user
    if newsletter.valid?
      NewsletterEntry.create(newsletter, user)
    end
    head :ok
  end

end
