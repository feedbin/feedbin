class NewslettersController < ApplicationController

  skip_before_action :verify_authenticity_token
  skip_before_action :authorize

  def create
    newsletter = Newsletter.new(params)
    if newsletter.valid?
      create_newsletter(newsletter)
    end
    head :ok
  end

  private

  def create_newsletter(newsletter)
    if user = User.where(newsletter_token: newsletter.token).take
      entry = build_entry(newsletter)
      feed = get_feed(newsletter)
      user.subscriptions.find_or_create_by(feed: feed)
      feed.entries.create!(entry)
      feed.feed_type = :newsletter
      feed.options["email_headers"] = newsletter.headers
      feed.save
    end
  end

  def build_entry(newsletter)
    {
      author: newsletter.from_name,
      content: newsletter.content,
      title: newsletter.subject,
      url: newsletter_entry_url(newsletter.entry_id),
      entry_id: newsletter.entry_id,
      published: Time.now,
      updated: Time.now,
      public_id: newsletter.entry_id,
      data: {newsletter_text: newsletter.text, type: "newsletter", format: newsletter.format}
    }
  end

  def get_feed(newsletter)
    Feed.where(feed_url: newsletter.feed_url).first_or_create(
      title: newsletter.from_name,
      feed_url: newsletter.feed_url,
      site_url: newsletter.site_url,
      feed_type: :newsletter
    )
  end

end


