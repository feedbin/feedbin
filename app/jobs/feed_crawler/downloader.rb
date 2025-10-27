module FeedCrawler
  class Downloader
    include Sidekiq::Worker
    include SidekiqHelper

    sidekiq_options queue: :crawl, retry: false, backtrace: false

    attr_accessor :critical

    def perform(feed_id, feed_url, subscribers, crawl_data = {})
      @feed_id     = feed_id
      @feed_url    = feed_url
      @subscribers = subscribers
      @crawl_data  = CrawlData.new(crawl_data)
      @parsing     = false

      download
    ensure
      persist_crawl_data unless @parsing
    end

    def download
      Sidekiq.logger.info "Downloading url=#{@feed_url} last_download=#{@crawl_data.downloaded_ago}"

      @crawl_data.log_download

      @response = begin
        request
      rescue Feedkit::ZlibError
        request(auto_inflate: false)
      end

      content_changed = !@response.not_modified?(@crawl_data.download_fingerprint)

      @crawl_data.download_success(@feed_id, redirects: @response.redirects)
      @crawl_data.save(@response)
      UpdateRedirect.perform_async(@feed_id, @crawl_data.redirected_to) if @crawl_data.redirect_changed?

      message = "Downloaded content_changed=#{content_changed} http_status=\"#{@response.status}\" url=#{@feed_url} server=\"#{@response.headers.get(:server).last}\""
      if @crawl_data.relative_retry_after > 0
        message = "#{message} throttled_next_retry=#{@crawl_data.relative_retry_after}"
      end
      Sidekiq.logger.info message

      parse if content_changed
    rescue Feedkit::Error => exception
      @crawl_data.download_error(exception)
      message = "Feedkit::Error: attempts=#{@crawl_data.error_count} exception=#{exception.inspect} id=#{@feed_id} url=#{@feed_url} next_retry=#{@crawl_data.relative_retry_after}"
      if exception.respond_to?(:response)
        message = "#{message} server=#{exception.response.headers[:server]}"
      end
      Sidekiq.logger.info message
    end

    def request(auto_inflate: true)
      parsed_url = Feedkit::BasicAuth.parse(@feed_url)
      url = @crawl_data.redirected_to ? @crawl_data.redirected_to : parsed_url.url
      Sidekiq.logger.info "Redirect: from=#{@feed_url} to=#{@crawl_data.redirected_to} id=#{@feed_id}" if @crawl_data.redirected_to

      Feedkit::Request.download(url,
        username:      parsed_url.username,
        password:      parsed_url.password,
        last_modified: @crawl_data.last_modified,
        etag:          @crawl_data.etag,
        auto_inflate:  auto_inflate,
        user_agent:    "Feedbin feed-id:#{@feed_id} - #{@subscribers} subscribers"
      )
    end

    def parse
      @parsing = true
      @response.persist!
      job_class = critical ? ParserCritical : Parser
      job_id = job_class.perform_async(@feed_id, @response.path, @response.encoding.to_s, @crawl_data.to_h)
      Sidekiq.logger.info "Parse enqueued job_id=#{job_id} path=#{@response.path}"
    end

    def persist_crawl_data
      add_to_queue(PersistCrawlData::SET_NAME, {
        id: @feed_id,
        crawl_data: @crawl_data.to_h
      }.to_json)
    end
  end
end