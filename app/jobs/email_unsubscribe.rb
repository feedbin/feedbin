class EmailUnsubscribe
  include Sidekiq::Worker

  def perform(feed_id)
    feed = Feed.where(id: feed_id, feed_type: Feed.feed_types[:newsletter]).take!
    if options = feed.list_unsubscribe
      options.scan(/<(.*?)>/).flatten.each do |option|
        if option.start_with?("mailto:")
          parser = MailtoParser.new(option)
          email = {
            to: parser.email,
            subject: parser.params["subject"] || "",
            body: parser.params["body"] || ""
          }
          ActionMailer::Base.mail(email).deliver_now
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
  end

end
