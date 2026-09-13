# One-time: copy every legacy favicon object into the unified store and
# write its images row, so the favicons table can retire with no host
# losing its icon. A copy, not a crawl: the legacy bucket already holds a
# processed 32x32 PNG per host, and copying it covers dead hosts and hosts
# that block the pipeline's user agent, which a re-crawl would lose.
#
# Fan-out in the SidekiqHelper style: perform(nil, true) pushes one job per
# SidekiqHelper::BATCH_SIZE favicon ids at once, and the utility workers
# drain them. No spread: the copy talks only to S3 and the unified store,
# so third-party rate limits do not apply, and the utility queue's weight
# keeps live work ahead.
class BackfillFavicons
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :backfill

  # Rows with no website_favicon row for their lower-cased host. A LEFT
  # JOIN anti-join, not NOT IN: NOT IN never becomes an anti-join in
  # Postgres. Arel rather than where.missing because the copy lower-cases
  # the host and an association cannot join on lower(host). unscoped: the
  # default scope's column select breaks count and the join.
  def self.pending
    favicons = Favicon.arel_table
    images = Image.arel_table
    lower_host = Arel::Nodes::NamedFunction.new("lower", [favicons[:host]])
    join = favicons.outer_join(images).on(
      images[:provider].eq(Image.providers[:website_favicon]).and(images[:provider_id].eq(lower_host))
    ).join_sources
    Favicon.unscoped.joins(join).where(images[:id].eq(nil))
  end

  # A hash condition, not a SQL fragment: the join brings images into the
  # query, and a bare "id" is ambiguous once both tables are in scope.
  def self.batch_scope(batch)
    ids = new.build_ids(batch)
    pending.where(id: ids.first..ids.last)
  end

  def perform(batch = nil, schedule = false)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    if schedule
      build
    else
      update(batch)
    end
  end

  def build
    last_id = Favicon.unscoped.maximum(:id)
    return unless last_id

    job_args(last_id, Favicon.unscoped.minimum(:id)).each_slice(100) do |jobs|
      Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class)
    end
  end

  # Reruns are safe: a copied host leaves pending, and create_image upserts
  # by (provider, host) onto a content-addressed path, so a host copied
  # twice in flight writes one row and orphans nothing.
  def update(batch)
    rows = self.class.batch_scope(batch).select(:id, :host, :url).order(:id).to_a
    client = Image.unified_client
    copied = rows.count { Copy.new(it, client).call }
    logger.info "BackfillFavicons: batch=#{batch} scanned=#{rows.size} copied=#{copied} skipped=#{rows.size - copied}"
  end

  # One legacy favicon into the unified store. Returns true when a row was
  # written. Never raises for one host: a raise abandons the rest of the
  # batch, and a host that cannot be copied simply stays pending. A storage
  # error is the exception, see STORE_ERRORS.
  class Copy
    # Storage errors are batch-level, not per-host: a missing bucket, bad
    # credentials, or an outage would otherwise turn a whole batch into
    # "skipped" lines that Sidekiq marks complete. Re-raised so Sidekiq
    # retries the batch; a copied host leaves pending, so the retry resumes
    # at the first host that was not copied.
    STORE_ERRORS = [Excon::Error, Fog::Errors::Error].freeze

    # client is built once per batch, outside the per-host rescue: a client
    # that cannot be built is a configuration error, and that must abort the
    # batch.
    def initialize(favicon, client)
      @favicon = favicon
      @client = client
    end

    def call
      path = download
      return false if path.nil?

      unless ImageFormat.allowed?(path)
        log("not an image")
        return false
      end

      image = build(path)
      File.open(path) do |file|
        @client.put_object(image.unified_bucket, image.storage_path, file, image.unified_storage_options)
      end
      image.create_image
      true
    rescue *STORE_ERRORS
      raise
    rescue => exception
      log("copy failed exception=#{exception.inspect}")
      false
    ensure
      FileUtils.rm_f(path) if path
    end

    private

    def host
      @favicon.host.to_s.downcase
    end

    # The object URL the writer recorded, fetched over HTTP: the objects
    # were uploaded public-read, and a key derived from data["favicon_hash"]
    # is not reliable (older rows shard on four characters, newer on three).
    # block_ssrf: the URL comes from a database row, and the objects live on
    # public S3 addresses, so the guard costs nothing.
    def download
      Feedkit::Request.download(@favicon.url, block_ssrf: true).persist!
    rescue Feedkit::Error => exception
      log("download failed exception=#{exception.inspect}")
      nil
    end

    # The copied bytes are both the original and the processed bytes, so
    # both fingerprints are the same MD5, and storage_path derives from it:
    # two hosts with byte-identical legacy PNGs share one object. url is the
    # legacy URL, so the first live crawl sends an unconditional GET (a
    # candidate never matches it) and processes (its original bytes never
    # fingerprint to a processed PNG). One extra pass per host, once.
    def build(path)
      processed = ImageCrawler::Processor::Processed.new(path, "png")
      fingerprint = processed.fingerprint
      ImageCrawler::Image.new_with_attributes(
        id: "#{host}-favicon",
        kind: ::Image.kinds[:site_icon],
        preset_name: "favicon",
        image_urls: [],
        provider: ::Image.providers[:website_favicon],
        provider_id: host,
        original_url: @favicon.url,
        storage_url: @favicon.url,
        original_fingerprint: fingerprint,
        fingerprint: fingerprint,
        width: processed.width,
        height: processed.height,
        bytesize: processed.size,
        placeholder_color: processed.placeholder_color
      )
    end

    def log(message)
      Sidekiq.logger.info "BackfillFavicons::Copy: #{message} host=#{host} url=#{@favicon.url}"
    end
  end
end
