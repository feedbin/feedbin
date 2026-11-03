# Measures two costs of v3 polling on real data. Read-only: each runs in a
# READ ONLY transaction with a 30 second statement_timeout.
#
# 1. An empty arrivals page: GET /v3/entries with a received_asc cursor at
#    the user's newest entry, which is what a quiet poll asks (feedbin-api-docs
#    design.md, open question 20).
# 2. The ETags of the user's unread and starred id lists: the fingerprint
#    Api::V3::Conditional computes on every poll of /collections/{id}/ids,
#    the work a 304 still does.
#
# Usage: bin/rails runner script/measure_v3_sync.rb USER_ID

user_id = Integer(ARGV.first, exception: false)
abort "usage: bin/rails runner script/measure_v3_sync.rb USER_ID" unless user_id

user = User.find(user_id)
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
    cursor = {"sort" => "received_asc", "timestamp" => (newest.created_at.to_r * 1_000_000).to_i, "id" => newest.id}
    page = Api::V3::Timeline.page(base, "received_asc", limit: 100, cursor: cursor)
    explain(connection, page.relation.to_sql)
  else
    puts "  The user's feeds have no entries."
  end
end

puts
puts "== 2. Id list ETags for user #{user.id}"
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  connection.execute("SET LOCAL statement_timeout = '30s'")
  {"unread" => user.unread_entries, "starred" => user.starred_entries}.each do |name, scope|
    puts "  #{name}: #{scope.count} rows"
    explain(connection, scope.reorder(nil).select(Arel.sql("count(*), coalesce(sum(hashtext(concat_ws(':', entry_id))), 0)")).to_sql)
  end
end
