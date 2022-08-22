$LOAD_PATH.unshift File.expand_path(File.dirname(File.dirname(__FILE__)))

$stdout.sync = true

require "bundler/setup"
require "dotenv"

if ENV["ENV_PATH"]
  Dotenv.load ENV["ENV_PATH"]
else
  Dotenv.load
end

require "digest/sha1"
require "date"
require "socket"
require "time"
require "forwardable"
require "json"

require "sidekiq"
require "connection_pool"
require "redis"
require "feedkit"

require "lib/sidekiq"
require "lib/redis"
require "lib/cache"
require "lib/feed_status"
require "lib/redirect_cache"
require "lib/http_cache"
require "lib/feed"
require "lib/entry_filter"
require "lib/throttle"
require "lib/jobs/feed_parser"
require "lib/jobs/feed_downloader"
require "lib/jobs/twitter_refresher"
