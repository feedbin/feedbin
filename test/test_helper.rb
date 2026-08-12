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
require "support/stripe_payment_method_helper"
require "support/assertions"
require "support/api_controller_test_case"
require "support/push_server_mock"
require "component_test_case"

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = "./test/fixtures/stripe_webhooks/"
WebMock.disable_net_connect!(allow_localhost: true, allow: ENV['WEBMOCK_ALLOWED_HOSTS']&.split(","))
Sidekiq.logger.level = Logger::WARN

# fog-aws 3.33 builds DeleteObjects XML by mutating a string literal
# (delete_multiple_objects.rb), which Ruby 4 deprecation-warns about on every
# call. Silence that one gem warning until upstream is frozen-string-literal
# clean; everything else still warns.
module FogFrozenStringLiteralWarningFilter
  def warn(message, **)
    return if message.include?("fog-aws") && message.include?("literal string will be frozen")
    super
  end
end
Warning.extend(FogFrozenStringLiteralWarningFilter)


# Writer for ActiveSupport::TestCase#outside_transaction. Its own connection
# pool, named so that skip_transactional_tests_for_database can keep the
# fixture machinery from wrapping it in the test's transaction.
class OutsideTransaction < ActiveRecord::Base
  self.abstract_class = true

  DATABASE_NAME = "outside_transaction"

  # Until this class has a pool of its own it inherits ActiveRecord::Base's,
  # which is the pinned one the test runs in — so check the pool, not
  # connected?, which is true from the moment Base connects.
  def self.connect!
    return if connection_pool.db_config.name == DATABASE_NAME
    establish_connection(ActiveRecord::DatabaseConfigurations::HashConfig.new(
      Rails.env, DATABASE_NAME, ActiveRecord::Base.connection_pool.db_config.configuration_hash
    ))
  end

  def self.execute(sql, *binds)
    connection.execute(sanitize_sql_array([sql, *binds]))
  end
end

class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper
  include StripePaymentMethodHelper

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

  # Keep the outside_transaction pool out of the fixture transaction, which
  # otherwise wraps every pool established during a test.
  skip_transactional_tests_for_database(OutsideTransaction::DATABASE_NAME.to_sym)

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

  def with_env(vars)
    previous = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def parse_json
    JSON.parse(@response.body)
  end

  # Yields a writer on its own connection pool, outside the transaction the
  # test runs in, for reproducing races against a unique index — the losing
  # INSERT only raises if the winning row is committed by someone else.
  #
  # Rows written here are committed and outlive the test's rollback, so the
  # caller must clean them up from after_teardown — a DELETE issued while the
  # test still holds uncommitted rows for the same key waits on them.
  def outside_transaction
    OutsideTransaction.connect!
    yield OutsideTransaction
  end

  # Temporarily replaces a constant for the block — for thresholds a test
  # would otherwise have to loop hundreds of real iterations to cross.
  def swap_const(mod, name, value)
    original = mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, original)
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


  # Every SELECT issued during the block, so a test can assert on the shape of
  # the query rather than only on the answer it produced.
  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
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

  # Empties the search indexes without deleting them — index creation is far
  # more expensive than a match_all delete_by_query, and this runs in the
  # setup of every search-adjacent test. Falls back to recreating via
  # Search.setup when an alias is missing (a test deleted or swapped the
  # physical index behind it).
  def clear_search
    Search.client do |client|
      # delete_by_query only sees documents a refresh has made visible, so
      # without this a doc indexed by an earlier test and never refreshed
      # would survive the wipe and haunt a later search.
      client.refresh
      [Entry, Action, Feed].map { Search.index_name(_1.table_name) }.each do |alias_name|
        response = clear_index(client, alias_name)
        if response.key?("error")
          Search.setup
          clear_index(client, alias_name)
        end
      end
    end
  end

  def clear_index(client, alias_name)
    client.request(:post, "/#{alias_name}/_delete_by_query",
      params: {refresh: "true", conflicts: "proceed"},
      json: {query: {match_all: {}}})
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
