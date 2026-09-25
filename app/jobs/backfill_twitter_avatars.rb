# One-time: copy every Twitter avatar the icon proxy cached into the image
# store, one images row per Twitter URL, so remote_files, the proxy and the
# legacy icons bucket can go. A copy, not a crawl: the legacy objects are
# already 400x400 limit_crops, and most Twitter URLs are dead.
#
# perform(nil, true) pushes one job per BATCH_SIZE remote_files ids at once;
# a batch whose rows are all copied costs one query, so a second kickoff
# resumes where the first stopped. sizing reports what a run will cost.
class BackfillTwitterAvatars
  include Sidekiq::Worker
  sidekiq_options queue: :backfill

  BATCH_SIZE = 250

  # The legacy icon preset's bounding box: the objects are copied as they
  # are, so the variant is the one they were cropped to.
  VARIANT = "400x400".freeze

  CONTENT_TYPES = {"jpg" => "image/jpeg", "png" => "image/png"}.freeze

  TWITTER_PREFIXES = %w[
    https://pbs.twimg.com/
    http://pbs.twimg.com/
    https://abs.twimg.com/
    http://abs.twimg.com/
  ].freeze

  def self.twitter_rows
    RemoteFile.where(RemoteFile.arel_table[:original_url].matches_any(TWITTER_PREFIXES.map { "#{it}%" }))
  end

  # Rows with no twitter_avatar image yet, an anti-join (Image.outer_join).
  # The fingerprint column is uuid and reads back dashed; provider_id is
  # bare hex, so the join strips the dashes.
  def self.pending
    remote = RemoteFile.arel_table
    bare = Arel::Nodes::NamedFunction.new("replace", [Image.as_text(remote[:fingerprint]), Arel::Nodes.build_quoted("-"), Arel::Nodes.build_quoted("")])
    join = Image.outer_join(remote, provider: :twitter_avatar, key: bare).join_sources

    twitter_rows.joins(join).where(Image.arel_table[:id].eq(nil))
  end

  def self.batch_for(id)
    ((id - 1) / BATCH_SIZE) + 1
  end

  def self.batch_range(batch)
    first = ((batch - 1) * BATCH_SIZE) + 1
    first..(first + BATCH_SIZE - 1)
  end

  # Ids do not start at 1 once anything upstream is deleted.
  def self.batches
    first_id = RemoteFile.minimum(:id)
    last_id = RemoteFile.maximum(:id)
    return nil if first_id.nil? || last_id.nil?
    batch_for(first_id)..batch_for(last_id)
  end

  # What a copy run will cost, from a production console. Writes nothing:
  # the sample runs Copy#prepare, which downloads and decodes but never
  # uploads or writes a row. Every value is its own line, because a pasted
  # console block echoes only its last expression.
  def self.sizing(sample: 200, out: $stdout)
    remote = RemoteFile.arel_table
    host = Arel::Nodes::NamedFunction.new("substring", [remote[:original_url], Arel::Nodes.build_quoted("^[a-z]+://([^/]+)")])
    pending_count = pending.count

    out.puts "remote_files rows: #{RemoteFile.count}"
    out.puts "top hosts:"
    RemoteFile.group(host).order(Arel.star.count.desc).limit(20).count.each do |name, count|
      out.puts "  #{name || "(no host)"}: #{count}"
    end
    out.puts "twitter rows: #{twitter_rows.count}"
    out.puts "pending rows: #{pending_count}"
    out.puts "kickoff batches: #{batches&.size || 0}"
    out.puts "images rows with provider remote_file: #{Image.provider_remote_file.count}"

    results = sample_rows(sample, out)
    report_sample(results, pending_count, out)
    nil
  end

  def self.sample_rows(sample, out)
    rows = pending.order(Arel.sql("random()")).limit(sample).to_a
    rows.each.with_index(1).map do |row, index|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = begin
        Copy.new(row).prepare { |prepared| {ok: true, extension: prepared.extension, bytesize: prepared.bytesize} }
      rescue Copy::RowError => exception
        {ok: false, reason: exception.message}
      end
      out.puts "  sampled #{index}/#{rows.size}" if (index % 25).zero?
      result.merge(seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end
  end

  def self.report_sample(results, pending_count, out)
    out.puts "sample: #{results.size}"
    return if results.empty?

    copied, failed = results.partition { it[:ok] }
    out.puts "failed: #{(failed.size * 100.0 / results.size).round(1)}%"
    failed.group_by { it[:reason] }.each { |reason, group| out.puts "  #{reason}: #{group.size}" }
    out.puts "formats: #{copied.group_by { it[:extension] }.map { |extension, group| "#{extension}=#{group.size}" }.join(" ")}"

    sizes = copied.map { it[:bytesize] }.sort
    if sizes.any?
      mean = sizes.sum / sizes.size.to_f
      out.puts "bytes mean: #{mean.round} p95: #{sizes[(sizes.size * 0.95).ceil - 1]}"
      out.puts "estimated total bytes: #{(mean * pending_count).round} (#{ActiveSupport::NumberHelper.number_to_human_size(mean * pending_count)})"
    end

    seconds = results.sum { it[:seconds] } / results.size
    out.puts "seconds per row (download + decode, no upload): #{seconds.round(3)}"
    out.puts "estimated thread-hours: #{(seconds * pending_count / 3600).round(1)}"
  end

  def perform(batch = nil, schedule = false)
    if schedule
      build
    else
      update(batch)
    end
  end

  def build
    batches = self.class.batches
    return if batches.nil?
    Sidekiq::Client.push_bulk("args" => batches.zip, "class" => self.class)
  end

  # Copies the batch's pending rows one at a time. A row error is logged and
  # skipped: the row stays pending and shows up in pending.count. Anything
  # else (the store, the database) raises, and Sidekiq retries the batch.
  def update(batch)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.storage_configured?

    rows = self.class.pending.where(id: self.class.batch_range(batch)).order(:id).to_a
    copied = 0
    skipped = 0

    rows.each do |row|
      Copy.new(row).call
      copied += 1
    rescue Copy::RowError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
      skipped += 1
      logger.info "BackfillTwitterAvatars: skipped fingerprint=#{TwitterAvatar.fingerprint(row.original_url)} url=#{row.original_url} reason=#{exception.message}"
    end

    logger.info "BackfillTwitterAvatars: batch=#{batch} scanned=#{rows.size} copied=#{copied} skipped=#{skipped}"
    [copied, skipped]
  end

  # One legacy object, downloaded and read, ready to store unchanged.
  Prepared = Data.define(:path, :extension, :width, :height, :bytesize, :fingerprint, :placeholder_color) do
    # Content-addressed on the bytes: identical avatars share one object.
    def storage_path
      Image.content_storage_path_for(fingerprint, VARIANT, extension)
    end

    def content_type
      CONTENT_TYPES.fetch(extension)
    end
  end

  class Copy
    RowError = Class.new(StandardError)

    EXTENSIONS = {jpeg: "jpg", png: "png"}.freeze

    def initialize(remote_file)
      @remote_file = remote_file
    end

    def call
      prepare do |prepared|
        File.open(prepared.path) do |file|
          Image.storage_client.put_object(Image.bucket, prepared.storage_path, file, {
            "Content-Type"  => prepared.content_type,
            "Cache-Control" => "max-age=315360000, public, immutable"
          })
        end

        Image.attach!(
          provider: Image.providers[:twitter_avatar],
          # The proxy's own key: the fingerprint of the URL readers ask for,
          # which pending joins on too. original_url is where the bytes
          # came from and can differ.
          provider_id: Image.normalize_fingerprint(@remote_file.fingerprint),
          kind: Image.kinds[:avatar],
          feed_id: nil,
          url: @remote_file.original_url,
          variant: VARIANT,
          image_fingerprint: prepared.fingerprint,
          original_fingerprint: prepared.fingerprint,
          storage_path: prepared.storage_path,
          width: prepared.width,
          height: prepared.height,
          bytesize: prepared.bytesize,
          placeholder_color: prepared.placeholder_color,
          data: {"source" => "remote_files"}
        )
      end
    end

    # Download, format check, metadata: everything short of writing. Shared
    # with sizing, which must measure exactly what the copy will do. The file
    # is removed whatever the block does.
    def prepare
      path = download
      extension = EXTENSIONS[ImageFormat.detect(path)]
      raise RowError, "unsupported format" if extension.nil?

      yield read(path, extension)
    ensure
      FileUtils.rm_f(path) if path
    end

    private

    # The objects were uploaded public-read. block_ssrf: the URL comes from a
    # database row, and the objects live on public bucket addresses, so the
    # guard costs nothing.
    def download
      Feedkit::Request.download(@remote_file.storage_url, block_ssrf: true).persist!
    rescue Feedkit::Error => exception
      raise RowError, "download failed (#{exception.class})"
    end

    # placeholder_color decodes every pixel, so a corrupt body fails here and
    # not in the block.
    def read(path, extension)
      processed = ImageCrawler::Processor::Processed.new(path)
      Prepared.new(
        path: path,
        extension: extension,
        width: processed.width,
        height: processed.height,
        bytesize: processed.size,
        fingerprint: processed.fingerprint,
        placeholder_color: processed.placeholder_color
      )
    rescue Vips::Error
      raise RowError, "undecodable"
    end
  end
end
