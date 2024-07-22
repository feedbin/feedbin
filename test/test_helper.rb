ENV["RAILS_ENV"] ||= "test"

require "minitest"
require "minitest/mock"
require "socket"
require "connection_pool"

# unless ENV["CI"]
#   socket = Socket.new(:INET, :STREAM, 0)
#   socket.bind(Addrinfo.tcp("127.0.0.1", 0))
#   port = socket.local_address.ip_port
#   socket.close
#
#   ENV["REDIS_URL"] = "redis://localhost:%d" % port
#   redis_test_instance = IO.popen("redis-server --port %d --save '' --appendonly no" % port)
#
#   Minitest.after_run do
#     Process.kill("INT", redis_test_instance.pid)
#   end
# end

$redis = {
  entries: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) },
  refresher: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) }
}

require File.expand_path("../../config/environment", __FILE__)

require "rails/test_help"
require "sidekiq/testing"
require "webmock/minitest"
require "phlex/testing/nokogiri"
require "phlex/testing/rails/view_helper"

require "support/login_helper"
require "support/factory_helper"
require "support/assertions"
require "support/api_controller_test_case"
require "support/push_server_mock"
require "component_test_case"

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = "./test/fixtures/stripe_webhooks/"
WebMock.disable_net_connect!(allow_localhost: true)
Sidekiq.logger.level = Logger::WARN

class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper

  fixtures :all

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


  def stub_request_file(file, url, response_options = {})
    options = {body: File.new(support_file(file)), status: 200}.merge(response_options)
    stub_request(:get, url)
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
    Search.client { _1.request(:delete, Entry.table_name) }
    Search.client { _1.request(:delete, Action.table_name) }

    Search.client { _1.request(:put, Entry.table_name, json: $search[:config][:mappings][:entries]) }
    Search.client { _1.request(:put, Action.table_name, json: $search[:config][:mappings][:actions]) }
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