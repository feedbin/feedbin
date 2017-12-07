class Twitter::TweetPresenter < BasePresenter

  YOUTUBE_URLS = [
    %r(https?://youtu\.be/(.+)),
    %r(https?://www\.youtube\.com/watch\?v=(.*?)(&|#|$)),
    %r(https?://m\.youtube\.com/watch\?v=(.*?)(&|#|$)),
    %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)),
    %r(https?://www\.youtube\.com/v/(.*?)(#|\?|$)),
    %r(https?://www\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b)
  ]

  presents :tweet

  def text
    if tweet_hash[:entities]
      Twitter::Autolink.auto_link_with_json(tweet_hash[:full_text], tweet_hash[:entities]).html_safe
    else
      tweet_hash[:full_text]
    end
  end

  def main_tweet
    (tweet.retweeted_status?) ? tweet.retweeted_status : tweet
  end

  def tweet_hash
    @tweet_hash ||= main_tweet.to_h
  end

  def name
    main_tweet.user.name
  end

  def screen_name
    "@" + main_tweet.user.screen_name
  end

  def user_url
    "https://twitter.com/#{main_tweet.user.screen_name}"
  end

  def media
    main_tweet.media
  end

  def urls
    main_tweet.urls
  end

  def retweeted_message
    "Retweeted by " + (tweet.user.name || "@" + tweet.user.screen_name)
  end

  def retweeted_image
    if tweet.user.profile_image_uri?
      tweet.user.profile_image_uri("normal")
    else
      # default twitter avatar
    end
  end

  def profile_image_uri
    if main_tweet.user.profile_image_uri?
      main_tweet.user.profile_image_uri("bigger")
    else
      # default twitter avatar
    end
  end

  def find_video_url(variants)
    video = variants.max_by do |element|
      if element.content_type == "video/mp4" && element.bitrate
        element.bitrate
      else
        0
      end
    end

    video.url.to_s
  end

  def youtube_embed(url)
    url = url.expanded_url.to_s
    if YOUTUBE_URLS.find { |format| url =~ format } && $1
      youtube_id = $1
      @template.content_tag(:iframe, "", src: "https://www.youtube.com/embed/#{youtube_id}", height: 9, width: 16, frameborder: 0, allowfullscreen: true).html_safe
    else
      false
    end
  end

  def created_at
    # 12:08 PM - 6 Nov 2017
    main_tweet.created_at.strftime("%l:%M %p - %e %b %Y")
  end

  def created_at_display
    # 12:08 PM - 6 Nov 2017
    main_tweet.created_at.to_s(:full_human)
  end

  def location
    (main_tweet.place?) ? main_tweet.place.full_name : nil
  end
end