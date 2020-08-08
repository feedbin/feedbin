class PushUnsubscribe
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(feed_id, topic)
    feed = Feed.find(feed_id)
    secret = Push.hub_secret(feed.id)
    uri = URI(ENV["PUSH_URL"])

    feed.hubs.each do |hub|
      HTTP.timeout(write: 5, connect: 5, read: 5).follow(max_hops: 2).post(hub, form: {
        "hub.mode"     => "unsubscribe",
        "hub.verify"   => "async",
        "hub.topic"    => feed.self_url,
        "hub.secret"   => secret,
        "hub.callback" => Rails.application.routes.url_helpers.push_feed_url(feed, protocol: uri.scheme, host: uri.host)
      })
    end

  end
end
