# One-time: copy every avatar the icon proxy cached into the unified store
# and write its images row, so the proxy and the remote_files table can
# retire with no tweet or embed card losing its picture. A copy, not a
# crawl: the legacy bucket already holds the bytes, and most of the source
# urls are Twitter's and dead.
#
# Fan-out: perform(nil, true) pushes one job per BATCH_SIZE remote_files
# ids at once, on the backfill queue. No spread: the copy talks only to the
# legacy bucket and the unified store, so third-party rate limits do not
# apply. 2.4 million rows is about 9,600 batches; the wall clock is that
# count divided by the queue's thread count. from_batch lets a second
# kickoff continue where the first stopped.
#
# Each batch copies its rows one at a time, so throughput is the number of
# batch jobs running at once and the tail is the length of one batch. 250
# ids is a few minutes of one thread.
class BackfillAvatarCopies
  include Sidekiq::Worker
  sidekiq_options queue: :backfill

  BATCH_SIZE = 250

  # Rows with no remote_file row for their fingerprint. A LEFT JOIN
  # anti-join, not NOT IN: NOT IN never becomes an anti-join in Postgres.
  # The fingerprint column is uuid and reads back dashed; provider_id is the
  # bare hex the rows carry, so the join strips the dashes. Arel.sql carries
  # only the type keyword.
  def self.pending
    remote = RemoteFile.arel_table
    images = Image.arel_table
    as_text = Arel::Nodes::NamedFunction.new("CAST", [remote[:fingerprint].as(Arel.sql("text"))])
    bare = Arel::Nodes::NamedFunction.new("replace", [as_text, Arel::Nodes.build_quoted("-"), Arel::Nodes.build_quoted("")])
    join = remote.join(images, Arel::Nodes::OuterJoin).on(
      images[:provider].eq(Image.providers[:remote_file]).and(images[:provider_id].eq(bare))
    ).join_sources

    RemoteFile.joins(join).where(images[:id].eq(nil))
  end

  # A hash condition, not a SQL fragment: the join brings images into the
  # query, and a bare "id" is ambiguous once both tables are in scope.
  def self.batch_scope(batch)
    first = ((batch - 1) * BATCH_SIZE) + 1
    pending.where(id: first..(first + BATCH_SIZE - 1))
  end

  def perform(batch = nil, schedule = false, from_batch = 1)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    if schedule
      build(from_batch)
    else
      update(batch)
    end
  end

  # push_bulk slices the push itself.
  def build(from_batch)
    last_id = RemoteFile.maximum(:id)
    return unless last_id

    last_batch = ((last_id - 1) / BATCH_SIZE) + 1
    jobs = (from_batch..last_batch).map { |batch| [batch] }
    Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class)
  end

  # Reruns are safe: a copied row leaves pending, and create_image upserts
  # by (provider, fingerprint) onto a content-addressed path, so a row
  # copied twice in flight writes one row and orphans nothing.
  def update(batch)
    rows = self.class.batch_scope(batch).select(:id, :fingerprint, :original_url, :storage_url).order(:id).to_a
    client = Image.unified_client
    copied = rows.count { Copy.new(it, client).call }
    logger.info "BackfillAvatarCopies: batch=#{batch} scanned=#{rows.size} copied=#{copied} skipped=#{rows.size - copied}"
  end

  # One legacy avatar into the unified store. Returns true when a row was
  # written. Never raises for one row: a raise abandons the rest of the
  # batch, and a row that cannot be copied simply stays pending. A storage
  # error is the exception, see STORE_ERRORS.
  class Copy
    # Storage errors are batch-level, not per-row: a missing bucket, bad
    # credentials, or an outage would otherwise turn a whole batch into
    # "skipped" lines that Sidekiq marks complete. Re-raised so Sidekiq
    # retries the batch; a copied row leaves pending, so the retry resumes
    # at the first row that was not copied.
    STORE_ERRORS = [Excon::Error, Fog::Errors::Error].freeze

    def initialize(remote_file, client)
      @remote_file = remote_file
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
      return false if image.nil?

      File.open(image.processed_path) do |file|
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
      FileUtils.rm_f(image.processed_path) if image&.processed_path
    end

    private

    def fingerprint
      @remote_file.fingerprint.to_s.delete("-")
    end

    # The object URL the proxy recorded, fetched over HTTP: the objects were
    # uploaded public-read. block_ssrf: the URL comes from a database row,
    # and the objects live on public bucket addresses, so the guard costs
    # nothing.
    def download
      Feedkit::Request.download(@remote_file.storage_url, block_ssrf: true).persist!
    rescue Feedkit::Error => exception
      log("download failed exception=#{exception.inspect}")
      nil
    end

    # Re-encoded to the icon preset's 200px png, the same processing a live
    # crawl would do, so the row is exactly what a crawler would have
    # written: a later crawl of the same url short-circuits on its
    # fingerprint. original_fingerprint is the legacy object's bytes; url
    # is the original url, so a micropost crawler's lookup by
    # url_fingerprint finds this row.
    def build(path)
      cropper = ImageCrawler::Processor::Cropper.new(path, crop: :limit_png, extension: ImageFormat.detect(path), width: 200, height: 200)
      unless cropper.valid?(false)
        log("undecodable")
        return nil
      end
      cropped = cropper.crop!

      ImageCrawler::Image.new_with_attributes(
        id: "#{fingerprint}-icon",
        kind: ::Image.kinds[:avatar],
        preset_name: "icon",
        image_urls: [],
        provider: ::Image.providers[:remote_file],
        provider_id: fingerprint,
        original_url: @remote_file.original_url,
        final_url: @remote_file.original_url,
        storage_url: @remote_file.storage_url,
        original_fingerprint: Digest::MD5.file(path).hexdigest,
        fingerprint: cropped.fingerprint,
        processed_path: cropped.file,
        processed_extension: cropped.extension,
        width: cropped.width,
        height: cropped.height,
        bytesize: cropped.size,
        placeholder_color: cropped.placeholder_color
      )
    end

    def log(message)
      Sidekiq.logger.info "BackfillAvatarCopies::Copy: #{message} fingerprint=#{fingerprint} url=#{@remote_file.original_url}"
    end
  end
end
