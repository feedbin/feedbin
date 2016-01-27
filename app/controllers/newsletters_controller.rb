class NewslettersController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  respond_to :json

  def create
    if inbound_message?
      events.each do |event|
        newsletter = Newsletter.new(event)
        if newsletter.valid?
          create_newsletter(newsletter)
        end
      end
    end
  ensure
    render nothing: true
  end

  private

  def create_newsletter(newsletter)
    if user = User.where(newsletter_token: newsletter.token).take
      feed_url = newsletter.feed_url
      feed = Feed.where(feed_url: feed_url).take || create_newsletter_feed(newsletter, feed_url, user)
      entry = {
        author: newsletter.from_name,
        content: newsletter.html,
        title: newsletter.subject,
        url: newsletter_entry_url(newsletter.entry_id),
        entry_id: newsletter.entry_id,
        published: Time.now,
        updated: Time.now,
        public_id: newsletter.entry_id,
        data: {newsletter_text: newsletter.text, type: "newsletter"}
      }
      feed.entries.create(entry)
      feed.update(feed_type: :newsletter)
    end
  rescue Exception => exception
    logger.info { exception.inspect }
    Honeybadger.notify(exception)
  end

  def inbound_message?
    params[:mandrill_events].present?
  end

  def events
    JSON.parse(params[:mandrill_events])
  end

  def create_newsletter_feed(newsletter, feed_url, user)
    feed = Feed.create(title: newsletter.from_name, feed_url: feed_url, site_url: newsletter.site_url, feed_type: :newsletter)
    user.safe_subscribe(feed)
    feed
  end

end


