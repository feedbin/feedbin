require "etc"

if Rails.env.production?
  Rails.application.config.after_initialize do
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveSupport.on_load(:active_record) do
      begin
        uri = URI.parse(ENV["DATABASE_URL"])
      rescue URI::InvalidURIError
        raise "Invalid DATABASE_URL"
      end

      database = (uri.path || "").split("/")[1]

      ActiveRecord::Base.establish_connection(
        adapter: "postgresql",
        host: uri.host,
        port: ENV["DB_PORT"]&.to_i || uri.port,
        username: uri.user,
        password: uri.password,
        database: database,
        reaping_frequency: ENV["DB_REAP_FREQ"] || 10,
        pool: ENV["DB_POOL"] || Etc.nprocessors,
        connect_timeout: 5,
        prepared_statements: ENV["PG_BOUNCER"]&.to_i == 1 ? false : true,
        advisory_locks: ENV["PG_BOUNCER"]&.to_i == 1 ? false : true,
        variables: {
          statement_timeout: ENV["DB_STATEMENT_TIMEOUT"] || "15s",
          lock_timeout: ENV["DB_LOCK_TIMEOUT"] || "10s"
        }
      )
    end
  end
end
