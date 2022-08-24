# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path(File.dirname(File.dirname(__FILE__)))

$stdout.sync = true

require "bundler/setup"
require "dotenv"
Dotenv.load(".env", ".env.test")

require "socket"
require "etc"
require "net/http"
require "securerandom"
require "time"
require "uri"
require "etc"
require "digest"

require "addressable"
require "dotenv"
require "down"
require "fog/aws"
require "http"
require "image_processing/vips"
require "json"
require "librato-rack"
require "mime-types"
require "open3"
require "redis"
require "shellwords"
require "sidekiq"

require "lib/crawler/initializers/constants"
require "lib/crawler/initializers/down"
require "lib/crawler/initializers/librato"
require "lib/crawler/initializers/worker_stat"
require "lib/crawler/initializers/sidekiq"
require "lib/crawler/initializers/storage"

require "lib/crawler/image/helpers"
require "lib/crawler/image/timer"
require "lib/crawler/image/cache"
require "lib/crawler/image/meta_images"
require "lib/crawler/image/meta_images_cache"
require "lib/crawler/image/download_cache"
require "lib/crawler/image/download"
require "lib/crawler/image/download/default"
require "lib/crawler/image/download/instagram"
require "lib/crawler/image/download/vimeo"
require "lib/crawler/image/download/youtube"
require "lib/crawler/image/image_processor"
require "lib/crawler/image/jobs/find_image"
require "lib/crawler/image/jobs/process_image"
require "lib/crawler/image/jobs/upload_image"
