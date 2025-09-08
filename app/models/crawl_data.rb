class CrawlData
  delegate :last_modified, :etag, :download_fingerprint, to: :@data
  delegate :redirected_to, :last_error, to: :@data

  attr_reader :data

  def initialize(data = {})
    @data = OpenStruct.new(data)
  end

  def error_count
    @data.error_count.to_i
  end

  def failed_at
    @data.failed_at.to_i
  end

  def ok?(feed_url)
    Time.now.to_i > retry_after
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

  def retry_after
    @data.retry_after.to_i
  end

  def relative_retry_after
    @data.retry_after.to_i - Time.now.to_i
  end

  def log_download
    @data.downloaded_at = Time.now.to_i
  end

  def download_success(feed_id, redirects: [])
    clear! unless last_error && last_error["class"] == "Feedkit::NotFeed"
    redirect = FeedCrawler::RedirectCache.new(feed_id).save(redirects)
    if redirect.present?
      @data.redirected_to = redirect
    end
  end

  def download_error(exception)
    @data.error_count = error_count + 1
    @data.failed_at   = Time.now.to_i
    @data.last_error  = error_data(exception)
    @data.retry_after = next_retry(exception)
  end

  def next_retry(exception)
    header = retry_after_header(exception).to_i
    default = @data.failed_at + backoff
    retry_after = [header, default].max
  end

  def save(response)
    @data.etag                 = response.etag
    @data.last_modified        = response.last_modified
    @data.download_fingerprint = response.checksum
    if retry_after = FeedCrawler::Throttle.retry_after(response.url)
      @data.retry_after = retry_after
    end
  end

  def clear!
    @data.failed_at   = nil
    @data.last_error  = nil
    @data.error_count = nil
    @data.retry_after  = nil
  end

  def ==(other)
    self.class == other.class && @data.to_h == other.to_h || super
  end

  def to_h
    @data.to_h
  end

  private

  def error_data(exception)
    {
      "date"    => Time.now.to_i,
      "class"   => exception.class.name,
      "message" => exception.message,
      "status"  => exception.try(:response).try(:status).try(:code)
    }
  end

  def retry_after_header(exception)
    return unless exception.respond_to?(:response)
    retry_after = exception.response.headers[:retry_after]
    return if retry_after.nil?
    retry_after = retry_after.strip

    retry_after = if retry_after.include?(" ")
      Time.parse(retry_after)
    else
      Time.at(Time.now.to_i + retry_after.to_i)
    end

    retry_after = [retry_after, 8.hours.from_now].min

    retry_after
  rescue
    nil
  end

  def backoff
    multiplier = [error_count, 8].max
    multiplier = [multiplier, 23].min
    multiplier ** 4
  end
end
