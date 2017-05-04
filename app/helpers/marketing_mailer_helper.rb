module MarketingMailerHelper
  def subscribe_url(feed_url)
    uri = URI::HTTP.build(
      host: Rails.application.config.action_mailer.default_url_options[:host],
      query: {subscribe: feed_url}.to_query
    )
    uri.scheme = "https"
    uri.to_s
  end
end
