# One-time migration of the parser's feed icon urls into feed_icon rows. The
# normal image pipeline downloads each url and attaches the row; this job
# only schedules.
#
# Fan-out in the SidekiqHelper style: perform(nil, true) pushes one job per
# SidekiqHelper::BATCH_SIZE feed ids, with `at` timestamps spaced evenly
# over SPREAD. The image queues are shared with live crawling and every feed
# costs a download from a third-party site, so the batches must not all land
# at once; the spread is the rate toward both.
class BackfillFeedIcons
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  SPREAD = 1.hour

  # Feeds with a legacy source in options and no feed_icon row. Podcasts are
  # excluded: ItunesFeedImage owns their row, and the ones without one are
  # its residual.
  #
  # The RSS image counts only for a micropost feed (entries, none titled),
  # which is the same test Feed#micropost? makes, here as two correlated
  # EXISTS on entries. Without it the set is 300k article feeds carrying a
  # banner, each declined by the job at two queries apiece. Scheduling is
  # not completion: check the row counts after the image queues drain.
  #
  # A hand-built LEFT JOIN anti-join, not where.missing and not
  # where.not(provider_id: subquery). NOT IN never becomes an anti-join in
  # Postgres, so it hashes every feed_icon provider_id per query and rescans
  # images per row once that hash outgrows work_mem. where.missing builds
  # the right join but compares images.provider_id (text) to feeds.id
  # (bigint), which Postgres refuses; the cast below is the fix, and the
  # join still rides index_images_on_provider_and_provider_id. Arel.sql
  # carries only the type keyword "text", never a value.
  def self.pending
    feeds = Feed.arel_table
    images = Image.arel_table
    feed_id_text = Arel::Nodes::NamedFunction.new("CAST", [feeds[:id].as(Arel.sql("text"))])
    join = feeds.join(images, Arel::Nodes::OuterJoin).on(
      images[:provider].eq(Image.providers[:feed_icon]).and(images[:provider_id].eq(feed_id_text))
    ).join_sources

    entries = Entry.arel_table
    has_entries = entries.project(1).where(entries[:feed_id].eq(feeds[:id])).exists
    has_titled_entry = entries.project(1).where(
      entries[:feed_id].eq(feeds[:id]).and(entries[:title].not_eq(nil)).and(entries[:title].not_eq(""))
    ).exists

    options = feeds[:options]
    source = json_text(options, "json_feed", "icon").not_eq(nil)
      .or(json_text(options, "json_feed", "author", "avatar").not_eq(nil))
      .or(json_text(options, "image", "url").not_eq(nil).and(has_entries).and(has_titled_entry.not))

    Feed.joins(join)
      .where(images[:id].eq(nil))
      .where(source)
      .where(json_text(options, "itunes_image").eq(nil))
  end

  # options is json, not jsonb: -> walks objects and ->> reads the leaf as
  # text. Arel quotes every key; nothing is interpolated.
  def self.json_text(column, *path)
    *objects, key = path
    node = objects.reduce(column) { |parent, name| Arel::Nodes::InfixOperation.new("->", parent, Arel::Nodes.build_quoted(name)) }
    Arel::Nodes::InfixOperation.new("->>", node, Arel::Nodes.build_quoted(key))
  end

  # The pending feeds whose id falls in one SidekiqHelper batch. A hash
  # condition, not a SQL fragment: the anti-join brings images into the
  # query, and a bare "id" is ambiguous once both tables are in scope.
  def self.batch_scope(batch)
    ids = new.build_ids(batch)
    pending.where(id: ids.first..ids.last)
  end

  # spread is in seconds; the operator's one rate knob, taken at schedule
  # time so a different pace needs no deploy.
  def perform(batch = nil, schedule = false, spread = SPREAD)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    if schedule
      build(spread)
    else
      update(batch)
    end
  end

  # Reruns are safe: a stored feed leaves pending, and image attachment
  # upserts by provider/feed, so a feed scheduled twice while in flight does
  # not create duplicate rows.
  def build(spread)
    last_id = Feed.maximum(:id)
    return unless last_id

    jobs = job_args(last_id, Feed.minimum(:id))
    now = Time.now.to_f
    step = spread.to_f / jobs.size
    at = jobs.each_index.map { |index| now + (index * step) }

    # push_bulk slices the push itself and pairs each job with its `at`.
    Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class, "at" => at)
  end

  def update(batch)
    feeds = self.class.batch_scope(batch).order(:id).to_a
    scheduled = 0

    feeds.each do |feed|
      if ImageCrawler::FeedIcon.schedule(feed, critical: false)
        scheduled += 1
      else
        logger.info "BackfillFeedIcons: declined feed_id=#{feed.id}"
      end
    end

    logger.info "BackfillFeedIcons: batch=#{batch} scanned=#{feeds.size} scheduled=#{scheduled} declined=#{feeds.size - scheduled}"
  end
end
