class CrawlData
  delegate :last_modified, :etag, :download_fingerprint, to: :@data
  delegate :redirected_to, :last_error, to: :@data

  attr_accessor :redirects

  def initialize(data = {})
    @data = OpenStruct.new(data)
    @redirects = []
  end

  def error_count
    @data.error_count.to_i
  end

  def failed_at
    @data.failed_at.to_i
  end

  def ok?(feed_url)
    return false if throttled?(feed_url)
    Time.now.to_i > next_retry
  end

  def throttled?(feed_url)
    FeedCrawler::Throttle.throttled?(feed_url, downloaded_at)
  end

  def downloaded_ago
    if downloaded_at == 0
      "never"
    else
      Time.now.to_i - downloaded_at
    end
  end

  def downloaded_at
    @data.downloaded_at.to_i
  end

  def log_download
    @data.downloaded_at = Time.now.to_i
  end

  def download_success(feed_id)
    clear! unless last_error && last_error["class"] == "Feedkit::NotFeed"
    redirect = FeedCrawler::RedirectCache.new(feed_id).save(redirects)
    if redirect.present?
      @data.redirected_to = redirect
    end
  end

  def download_error(exception)
    @data.error_count = error_count + 1
    @data.failed_at = Time.now.to_i
    @data.last_error = error_data(exception)
  end

  def clear!
    @data.failed_at = nil
    @data.last_error = nil
    @data.error_count = nil
  end

  def save(response)
    @data.etag                 = response.etag
    @data.last_modified        = response.last_modified
    @data.download_fingerprint = response.checksum
  end

  def ==(other)
    self.class == other.class && @data.to_h == other.to_h || super
  end

  def to_h
    @data.to_h
  end

  def next_retry
    failed_at + backoff
  end

  private

  def error_data(exception)
    {
      "date"        => Time.now.to_i,
      "class"       => exception.class.name,
      "message"     => exception.message,
      "status"      => exception.try(:response).try(:status).try(:code),
      "retry_after" => parse_retry_after(exception).to_i
    }
  end

  def parse_retry_after(exception)
    return unless exception.respond_to?(:response)
    retry_after = exception.response.headers[:retry_after]
    return if retry_after.nil?
    retry_after = retry_after.strip

    retry_after = if retry_after.include?(" ")
      Time.parse(retry_after)
    else
      Time.at(Time.now.to_i + retry_after.to_i)
    end

    [retry_after, 8.hours.from_now].min
  rescue
    nil
  end

  def backoff
    multiplier = [error_count, 8].max
    multiplier = [multiplier, 23].min
    multiplier ** 4
  end
end
