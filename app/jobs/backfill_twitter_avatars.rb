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
end
