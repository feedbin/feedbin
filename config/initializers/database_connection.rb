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
        port: uri.port,
        username: uri.user,
        password: uri.password,
        database: database,
        reaping_frequency: ENV["DB_REAP_FREQ"] || 10,
        pool: ENV["DB_POOL"] || Etc.nprocessors
      )
    end
  end
end
