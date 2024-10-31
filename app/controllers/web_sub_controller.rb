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
    content_type = request.headers["CONTENT_TYPE"]
    encoding = HTTP::ContentType.parse(request.headers["CONTENT_TYPE"]).charset || "UTF-8"
    body = request.raw_post
    if signature_valid?(body)
      body = body.force_encoding(encoding)
      path = File.join(Dir.tmpdir, "web_sub_#{SecureRandom.hex}")
      Rails.logger.info("web_sub content_type=#{content_type} path=#{path}")
      File.write(path, body)
      FeedCrawler::Parser.new.parse_and_save(@feed, path, encoding: encoding, web_sub: true)
    end
    head :ok
  rescue Encoding::UndefinedConversionError => exception
    ErrorService.notify(
      error_class: "WebSub",
      error_message: "UndefinedConversionError",
      parameters: {
        exception: exception,
        backtrace: exception.backtrace,
        body: request.raw_post
      }
    )
  rescue Feedkit::NotFeed
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
