class WebSubController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authorize
  before_action :set_feed

  def verify
    valid_topic = @feed.self_url == params["hub.topic"]
    if "subscribe" == params["hub.mode"] && valid_topic
      @feed.update(push_expiration: Time.now + (params["hub.lease_seconds"].to_i / 2).seconds)
      render plain: params["hub.challenge"]
    elsif "unsubscribe" == params["hub.mode"] && valid_topic
      @feed.update(push_expiration: nil)
      render plain: params["hub.challenge"]
    elsif "denied" == params["hub.mode"] && valid_topic
      @feed.update(push_expiration: Time.now + 1.week)
      ErrorService.notify(error_class: "WebSubController#denied", error_message: "Request denied", parameters: params)
      head :ok
    else
      head :not_found
    end
  end

  def publish
    body = request.raw_post
    if signature_valid?(body)
      parsed = Feedjira.parse(body)
      entries = parsed.entries.map do |entry|
        ActiveSupport::HashWithIndifferentAccess.new(Feedkit::Parser::XMLEntry.new(entry, @feed.feed_url).to_entry)
      end
      if entries.present?
        data = {
          "feed" => {"id" => @feed.id},
          "entries" => entries
        }
        video_ids = entries.map {|entry| entry.dig(:data, :youtube_video_id) }.compact
        if video_ids.present?
          HarvestEmbeds.new.add_missing_to_queue(video_ids)
          YoutubeReceiver.perform_in(2.minutes, data)
        else
          FeedCrawler::Receiver.new.perform(data)
        end
        Librato.increment "entry.push"
      end
    end
    head :ok
  rescue Feedjira::NoParserAvailable
    head :ok
  end

  private

  def signature_valid?(body)
    valid_algorithms = ["sha1", "sha256", "sha384", "sha512"]
    algorithm, signature = request.headers["HTTP_X_HUB_SIGNATURE"]&.split("=")
    valid_algorithms.include?(algorithm) && signature == OpenSSL::HMAC.hexdigest(algorithm, @feed.web_sub_secret, body)
  end

  def set_feed
    @feed = Feed.find(params[:id])
    render_404 unless params[:signature] == @feed.web_sub_callback_signature
  end
end
