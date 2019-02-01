class SendStats
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  MEGABYTE = 1024.0 * 1024.0

  def perform
    if ENV["LIBRATO_TOKEN"]
      memcached_stats
      redis_stats
      postgres_stats
      plan_count
      active_users_count
      queue_depth
      clear_empty_jobs
      sidekiq_queue_depth
    end
  end

  def sidekiq_queue_depth
    Sidekiq::Queue.all.each do |queue|
      Librato.measure "sidekiq.queue_depth.#{queue.name}", queue.size
    end
  end

  def clear_empty_jobs
    queue = Sidekiq::Queue.new("")
    queue.clear
  end

  def queue_depth
    socket = "/tmp/unicorn.sock"
    if File.exist?(socket)
      result = Raindrops::Linux.unix_listener_stats([socket])
      stats = result.values.first
      Librato.measure "server_queue_depth.active", stats.active, source: Socket.gethostname
      Librato.measure "server_queue_depth.queued", stats.queued, source: Socket.gethostname
    end
  end

  def active_users_count
    count = User.where(plan: Plan.where.not(price: 0), suspended: false).count
    Librato.measure("active_users_count", count)
  end

  def plan_count
    counts = User.where(suspended: false).group(:plan_id).count
    plans = Plan.all.index_by(&:id)
    counts.each do |plan_id, count|
      Librato.measure("plan_count", (plans[plan_id].price * count).to_i, source: plans[plan_id].stripe_id)
    end
  end

  def memcached_stats
    if Rails.cache.respond_to?(:stats)
      servers = Rails.cache.stats
      servers.each do |server, stats|
        server_name = server.gsub(/[^A-Za-z0-9]+/, "_")
        Librato.group "memcached.#{server_name}" do |group|
          group.measure("gets", stats["cmd_get"].to_f)
          group.measure("sets", stats["cmd_set"].to_f)
          group.measure("hits", stats["get_hits"].to_f)
          group.measure("items", stats["curr_items"].to_f)
          group.measure("connections", stats["curr_connections"].to_i)
        end
      end
    end
  end

  def redis_stats
    redis_info = Sidekiq.redis { |c| c.info }
    Librato.group "redis" do |group|
      group.measure("connected_clients", redis_info["connected_clients"].to_f)
      group.measure("used_memory", redis_info["used_memory"].to_f / MEGABYTE)
      group.measure("operations", redis_info["instantaneous_ops_per_sec"].to_f)
    end
  end

  def postgres_stats
    stats = []
    stats.concat(cache_hit)
    stats.concat(index_size)
    stats.concat(database_size)
    stats.each do |stat|
      Librato.measure("postgres.#{stat[:name]}", stat[:value], source: stat[:source])
    end
  end

  def cache_hit
    stats = []
    sql = "
      SELECT
        'index hit rate' AS name,
        (sum(idx_blks_hit)) / sum(idx_blks_hit + idx_blks_read) AS ratio
      FROM pg_statio_user_indexes
      UNION ALL
      SELECT
       'cache hit rate' AS name,
        sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS ratio
      FROM pg_statio_user_tables;
    "
    results = query(sql)
    results.each do |result|
      stats << {name: result["name"].gsub(/[^A-Za-z0-9]+/, "_"), value: result["ratio"].to_f}
    end
    stats
  end

  def index_size
    stats = []
    sql = '
      SELECT
        relname AS name,
        sum(relpages) AS size
      FROM pg_class
      WHERE reltype = 0
      GROUP BY relname
      ORDER BY sum(relpages) DESC;
    '
    results = query(sql)
    results.each do |result|
      size = (result["size"].to_f * 8) / 1024
      if size > 100
        stats << {name: "index_size", value: size, source: result["name"]}
      end
    end
    stats
  end

  def database_size
    stats = []
    database = ActiveRecord::Base.connection_config[:database]
    sql = %(
      SELECT pg_database_size('#{database}') as size;
    )
    results = query(sql)
    stats << {name: "database_size", value: results[0]["size"].to_f / MEGABYTE}
    stats
  end

  def query(sql)
    rows = []
    result = ActiveRecord::Base.connection.execute(sql)
    result.each do |row|
      rows << row
    end
    rows
  end
end
