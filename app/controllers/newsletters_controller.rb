class NewslettersController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  respond_to :json

  def create
    if inbound_message?
      events.each do |event|
        newsletter = Newsletter.new(event)
        if newsletter.valid?
          logger.info { "--------------------" }
          logger.info { newsletter.token.inspect }
          logger.info { newsletter.from_name.inspect }
          logger.info { newsletter.from_email.inspect }
          logger.info { "--------------------" }
        end
      end
    end
  ensure
    render nothing: true
  end

  private

  def inbound_message?
    params[:mandrill_events].present?
  end

  def events
    JSON.parse(params[:mandrill_events])
  end

end


