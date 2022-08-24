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

require "lib/crawler/refresher/initializers/sidekiq"
require "lib/crawler/refresher/initializers/redis"

require "lib/crawler/refresher/cache"
require "lib/crawler/refresher/feed_status"
require "lib/crawler/refresher/redirect_cache"
require "lib/crawler/refresher/http_cache"
require "lib/crawler/refresher/feed"
require "lib/crawler/refresher/entry_filter"
require "lib/crawler/refresher/throttle"
require "lib/crawler/refresher/jobs/feed_parser"
require "lib/crawler/refresher/jobs/feed_downloader"
require "lib/crawler/refresher/jobs/twitter_refresher"
