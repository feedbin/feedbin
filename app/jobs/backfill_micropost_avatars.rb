# One-time: run the micropost avatar pass over every micropost feed that has
# an entry without a row. Runs after BackfillAvatarCopies, so most avatar
# urls already have a copied row and the pass attaches rather than
# downloads.
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

  # Feeds carrying the parser's micropost marker (a cheap jsonb prefilter;
  # MicropostAvatar's own micropost? gate is the final word, and a micropost
  # feed the parser has not marked is picked up by its next crawl with new
  # posts) with at least one entry lacking an entry_icon row. The entry test
  # is a correlated EXISTS over the same anti-join the crawler uses, so the
  # two agree. Arel.sql carries only the type keyword.
  def self.pending
    feeds = Feed.arel_table
    entries = Entry.arel_table
    images = Image.arel_table
    entry_id_text = Arel::Nodes::NamedFunction.new("CAST", [entries[:id].as(Arel.sql("text"))])
    join = entries.join(images, Arel::Nodes::OuterJoin).on(
      images[:provider].eq(Image.providers[:entry_icon]).and(images[:provider_id].eq(entry_id_text))
    )
    row_less_entry = join.project(1).where(entries[:feed_id].eq(feeds[:id]).and(images[:id].eq(nil))).exists
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

    feeds.each do |feed|
      a, s = ImageCrawler::MicropostAvatar.schedule(feed, critical: false)
      attached += a
      scheduled += s
    end

    logger.info "BackfillMicropostAvatars: batch=#{batch} feeds=#{feeds.size} attached=#{attached} scheduled=#{scheduled}"
  end
end
