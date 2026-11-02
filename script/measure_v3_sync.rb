# Measures two costs the v3 design leaves open (feedbin-api-docs design.md,
# open questions 20 and 21), on real data:
#
# 1. An empty arrivals page: GET /v3/entries with a received_asc cursor at
#    the user's newest entry, which is what a quiet poll asks. Read-only: it
#    runs in a READ ONLY transaction.
# 2. The sync_versions trigger on fan-out: one unreads insert with a row per
#    active subscriber of FEED_ID, as a new entry makes. NOT read-only: the
#    insert really runs, then the transaction is rolled back. While it is
#    open it holds row locks on those users' sync_versions rows (the
#    trigger's upsert), so pick a quiet moment; statement_timeout caps it at
#    30 seconds. The rows are for the feed's oldest entry, which few
#    subscribers still have unread; rows that already exist are skipped, and
#    EXPLAIN reports how many were inserted.
#
# Usage: bin/rails runner script/measure_v3_sync.rb USER_ID FEED_ID

user_id, feed_id = ARGV.map { Integer(_1) }
abort "usage: bin/rails runner script/measure_v3_sync.rb USER_ID FEED_ID" unless user_id && feed_id

user = User.find(user_id)
feed = Feed.find(feed_id)
connection = ActiveRecord::Base.connection
$stdout.sync = true

def explain(connection, sql)
  connection.select_values("EXPLAIN (ANALYZE, BUFFERS) #{sql}").each { puts "  #{_1}" }
end

puts "== 1. Empty arrivals page for user #{user.id} (#{user.subscriptions.count} subscriptions)"
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  connection.execute("SET LOCAL statement_timeout = '30s'")
  base = Entry.where(feed_id: user.subscriptions.select(:feed_id))
  newest = base.order(created_at: :desc, id: :desc).first
  if newest
    page = base.where("(entries.created_at, entries.id) > (?, ?)", newest.created_at, newest.id).order(created_at: :asc, id: :asc).limit(101)
    explain(connection, page.to_sql)
  else
    puts "  The user's feeds have no entries."
  end
end

subscribers = Subscription.where(feed_id: feed.id, active: true).count
oldest = feed.entries.order(:id).first or abort "Feed #{feed.id} has no entries."
puts
puts "== 2. Unreads insert for #{subscribers} subscribers of feed #{feed.id} (rolled back)"
ActiveRecord::Base.transaction do
  connection.execute("SET LOCAL statement_timeout = '30s'")
  insert = ActiveRecord::Base.sanitize_sql_array([<<~SQL, feed_id: feed.id, entry_id: oldest.id])
    INSERT INTO unreads (user_id, feed_id, entry_id, published, entry_created_at, created_at, updated_at)
    SELECT user_id, feed_id, :entry_id, now(), now(), now(), now()
    FROM subscriptions
    WHERE feed_id = :feed_id AND active
    ON CONFLICT (user_id, entry_id) DO NOTHING
  SQL
  puts "  Entry #{oldest.id}. Tuples Inserted is the fan-out; the Trigger line is the sync_versions cost, included in Execution Time."
  explain(connection, insert)
  raise ActiveRecord::Rollback
end
puts
puts "Rolled back. unreads rows for entry #{oldest.id}: #{UnreadEntry.where(entry_id: oldest.id).count}"
