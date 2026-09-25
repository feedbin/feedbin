# One-time: run the micropost avatar pass over every micropost feed that has
# an entry without a row. Entries that share an avatar url share one
# download, and a url whose source is dead falls back to the object the
# proxy cached.
#
# Fan-out in the SidekiqHelper style: perform(nil, true) pushes one job per
# SidekiqHelper::BATCH_SIZE feed ids, with `at` timestamps spaced evenly
# over SPREAD. The downloads that remain hit third-party hosts on queues
# shared with live crawling; the spread is the rate.
class BackfillMicropostAvatars
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  SPREAD = 1.hour

  # Feeds carrying the parser's micropost marker with at least one untitled
  # entry lacking an entry_icon row. The marker is a cheap jsonb prefilter
  # and only this one-time job reads it; each entry's own micropost test
  # is the final word. A micropost feed without the marker is not covered
  # here; its new posts are, from its next crawl. The entry test is a
  # correlated EXISTS over the crawler's own anti-join and untitled filter
  # (MicropostAvatar.pending_entries), so the two agree.
  def self.pending
    feeds = Feed.arel_table
    entries = Entry.arel_table
    images = Image.arel_table
    join = Image.outer_join(entries, provider: :entry_icon, key: Image.as_text(entries[:id]))
    untitled = entries[:title].eq(nil).or(entries[:title].eq(""))
    row_less_entry = join.project(1).where(entries[:feed_id].eq(feeds[:id]).and(untitled).and(images[:id].eq(nil))).exists
    marker = Arel::Nodes::InfixOperation.new("->>", feeds[:settings], Arel::Nodes.build_quoted("custom_icon_format"))

    Feed.where(marker.eq("round")).where(row_less_entry)
  end

  # A hash condition, not a SQL fragment, qualified to feeds.
  def self.batch_scope(batch)
    ids = new.build_ids(batch)
    pending.where(id: ids.first..ids.last)
  end

  def perform(batch = nil, schedule = false, spread = SPREAD)
    raise "UNIFIED_BUCKET_IMAGES must be configured" unless Image.unified_enabled?

    if schedule
      build(spread)
    else
      update(batch)
    end
  end

  def build(spread)
    last_id = Feed.maximum(:id)
    return unless last_id

    jobs = job_args(last_id, Feed.minimum(:id))
    now = Time.now.to_f
    step = spread.to_f / jobs.size
    at = jobs.each_index.map { |index| now + (index * step) }

    Sidekiq::Client.push_bulk("args" => jobs, "class" => self.class, "at" => at)
  end

  def update(batch)
    feeds = self.class.batch_scope(batch).order(:id).to_a
    attached = 0
    scheduled = 0

    # One feed's error is logged and skipped: raising would strand the feeds
    # after it and send the whole batch back through Sidekiq's retries,
    # which pass every feed before it again. A skipped feed stays pending.
    feeds.each do |feed|
      a, s = ImageCrawler::MicropostAvatar.schedule(feed, critical: false)
      attached += a
      scheduled += s
    rescue => exception
      logger.info "BackfillMicropostAvatars: feed failed feed_id=#{feed.id} exception=#{exception.inspect}"
    end

    logger.info "BackfillMicropostAvatars: batch=#{batch} feeds=#{feeds.size} attached=#{attached} scheduled=#{scheduled}"
  end
end
