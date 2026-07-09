ENV["RAILS_ENV"] ||= "test"

require "minitest"
require "minitest/mock"
require "socket"
require "uri"
require "connection_pool"

unless ENV["CI"]
  socket = Socket.new(:INET, :STREAM, 0)
  socket.bind(Addrinfo.tcp("127.0.0.1", 0))
  port = socket.local_address.ip_port
  socket.close

  ENV["REDIS_URL"] = "redis://localhost:%d" % port
  redis_test_instance = IO.popen("redis-server --port %d --save '' --appendonly no --databases 32" % port)

  redis_parent_pid = Process.pid
  Minitest.after_run do
    Process.kill("INT", redis_test_instance.pid) if Process.pid == redis_parent_pid
  end
end

REDIS_BASE_URL = URI(ENV["REDIS_URL"] || "redis://localhost:6379").tap { _1.path = "" }.to_s

require File.expand_path("../../config/environment", __FILE__)

# MakeEpub's cover generation renders text with libvips, which on macOS
# lazily loads the CoreText backend on first use and triggers a one-time
# +[UIFontDescriptor initialize]. If that class-init is still running on a
# background thread the moment parallelize() below forks a worker, the
# child crashes the instant *it* touches the same class post-fork ("may
# have been in progress in another thread when fork() was called" -- macOS's
# objc runtime refuses to safely continue). Forcing the same call here,
# synchronously, in the single-threaded parent before any fork happens
# retires that one-time init early and removes the race. No-op cost on
# Linux CI (no objc runtime, but also nothing to warm).
Vips::Image.text("warmup", font: "Helvetica Bold 16") if RbConfig::CONFIG["host_os"].include?("darwin")

require "rails/test_help"
require "sidekiq/testing"
require "webmock/minitest"

require "support/login_helper"
require "support/factory_helper"
require "support/assertions"
require "support/api_controller_test_case"
require "support/push_server_mock"
require "component_test_case"

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = "./test/fixtures/stripe_webhooks/"
WebMock.disable_net_connect!(allow_localhost: true, allow: ENV['WEBMOCK_ALLOWED_HOSTS']&.split(","))
Sidekiq.logger.level = Logger::WARN


class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper

  parallelize(workers: :number_of_processors)

  parallelize_setup do |worker|
    ENV["TEST_WORKER"] = worker.to_s
    ENV["REDIS_URL"] = "#{REDIS_BASE_URL}/#{worker}"

    load Rails.root.join("config/initializers/redis.rb")
    Rails.cache = ActiveSupport::Cache.lookup_store(Rails.application.config.cache_store)
    Sidekiq.default_configuration.redis = {url: ENV["REDIS_URL"]}

    Search.configure!
    Search.setup
  end

  parallelize_teardown do
    Search.client do |client|
      # Search::ReindexFeeds swaps an alias's -01 index for a timestamped one,
      # so delete whatever indexes the worker's aliases point at now, then the
      # original physical names in case an index lost its alias.
      [Entry, Action, Feed].each do |model|
        client.get_indexes_from_alias(Search.index_name(model.table_name)).each do |index|
          client.delete_index(index)
        end
      end
      $search[:config][:aliases].each_value do |index|
        client.delete_index(index)
      end
    end
  end

  fixtures :all

  # Phlex testing helpers
  def render(...)
    view_context.render(...)
  end

  def view_context
    controller.view_context
  end

  def controller
    @controller ||= ActionView::TestCase::TestController.new
  end

  def flush_redis
    Sidekiq::Worker.clear_all

    Sidekiq.redis do |redis|
      redis.flushdb
    end
    $redis.each do |_, instance|
      instance.with do |redis|
        redis.flushdb
      end
    end
  end

  def parse_json
    JSON.parse(@response.body)
  end

  def support_file(file)
    File.join(Rails.root, "test/support/www", file)
  end

  def copy_support_file(file_name)
    path = File.join Dir.tmpdir, SecureRandom.hex
    FileUtils.cp File.join("test/support/www", file_name), path
    path
  end

  def load_xml
    File.read("test/support/www/atom.xml")
  end

  def random_string
    (0...50).map { ("a".."z").to_a[rand(26)] }.join
  end

  def aws_copy_body
    <<~EOT
      <?xml version="1.0" encoding="UTF-8"?>
      <CopyObjectResult>
         <ETag>string</ETag>
         <LastModified>Tue, 02 Mar 2021 12:58:45 GMT</LastModified>
      </CopyObjectResult>
    EOT
  end


  def stub_request_file(file, url, response_options = {}, method = :get)
    options = {body: File.new(support_file(file)), status: 200}.merge(response_options)
    stub_request(method, url)
      .to_return(options)
  end

  def load_tweet(option)
    load_support_json("tweet_#{option}")
  end

  def load_support_json(file_name)
    unless file_name.end_with?(".json")
      file_name = "#{file_name}.json"
    end
    JSON.parse(File.read(support_file(file_name)))
  end

  def create_stripe_plan(plan)
    Stripe::Plan.create(name: plan.name, id: plan.stripe_id, amount: plan.price.to_i, currency: "USD", interval: "day")
  end

  def clear_search
    Search.client { _1.request(:delete, $search[:config][:aliases][:entries]) }
    Search.client { _1.request(:delete, $search[:config][:aliases][:actions]) }
    Search.client { _1.request(:delete, $search[:config][:aliases][:feeds]) }

    Search.setup
  end

  def newsletter_params(recipient, signature, title = nil, from = nil)
    {
      newsletter: {
        to: recipient,
        url: "s3://bucket/path.to.email"
      }
    }
  end
end
