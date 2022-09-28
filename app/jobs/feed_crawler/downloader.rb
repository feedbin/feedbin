module FeedCrawler
  class Downloader
    include Sidekiq::Worker
    include SidekiqHelper

    sidekiq_options queue: :feed_downloader, retry: false, backtrace: false

    def perform(feed_id, feed_url, subscribers, critical = false, crawl_data = {})
      @feed_id     = feed_id
      @feed_url    = feed_url
      @subscribers = subscribers
      @critical    = critical
      @feed_cache  = FeedCache.new(feed_id)
      @crawl_data  = CrawlData.new(crawl_data)
      @updates     = {}

      throttle = Throttle.new(@feed_url, @feed_cache.downloaded_at)
      if @critical
        download
      elsif throttle.throttled?
        Sidekiq.logger.info "Throttled downloaded_at=#{Time.at(@feed_cache.downloaded_at)} url=#{@feed_url}"
      elsif @feed_cache.ok?
        download
      end
    ensure
      migrate_data
    end

    def download
      @feed_cache.log_download!
      @response = begin
        request
      rescue Feedkit::ZlibError
        request(auto_inflate: false)
      end

      not_modified = @response.not_modified?(@feed_cache.checksum)
      Sidekiq.logger.info "Downloaded modified=#{!not_modified} http_status=\"#{@response.status}\" url=#{@feed_url}"
      parse unless not_modified
      @feed_cache.download_success
    rescue Feedkit::Error => exception
      @feed_cache.download_error(exception)
      Sidekiq.logger.info "Feedkit::Error: attempts=#{@feed_cache.attempt_count} exception=#{exception.inspect} id=#{@feed_id} url=#{@feed_url}"
    end

    def request(auto_inflate: true)
      parsed_url = Feedkit::BasicAuth.parse(@feed_url)
      url = @feed_cache.redirect ? @feed_cache.redirect : parsed_url.url
      Sidekiq.logger.info "Redirect: from=#{@feed_url} to=#{@feed_cache.redirect} id=#{@feed_id}" if @feed_cache.redirect
      Feedkit::Request.download(url,
        on_redirect:   on_redirect,
        username:      parsed_url.username,
        password:      parsed_url.password,
        last_modified: @feed_cache.last_modified,
        etag:          @feed_cache.etag,
        auto_inflate:  auto_inflate,
        user_agent:    "Feedbin feed-id:#{@feed_id} - #{@subscribers} subscribers"
      )
    end

    def on_redirect
      proc do |from, to|
        @feed_cache.redirects.push Redirect.new(@feed_id, status: from.status.code, from: from.uri.to_s, to: to.uri.to_s)
      end
    end

    def parse
      @response.persist!
      job_class = @critical ? ParserCritical : Parser
      job_id = job_class.perform_async(@feed_id, @feed_url, @response.path, @response.encoding.to_s)
      Sidekiq.logger.info "Parse enqueued job_id: #{job_id} path=#{@response.path}"
      @feed_cache.save(@response)
    end

    def migrate_data
      @updates = {
        id: @feed_id,
        crawl_data: {
          etag:                 @feed_cache.etag,
          last_modified:        @feed_cache.last_modified,
          downloaded_at:        @feed_cache.downloaded_at,
          download_fingerprint: @feed_cache.checksum,
          error_count:          @feed_cache.attempt_count,
          redirected_to:        @feed_cache.redirect,
          last_error:           @feed_cache.last_error,
        }
      }
      add_to_queue(FeedCrawler::DownloaderMigration::SET_NAME, @updates.to_json)
    end
  end
end