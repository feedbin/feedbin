require "coveralls"
Coveralls.wear!("rails")

ENV["RAILS_ENV"] ||= "test"
ENV["REDIS_URL"] = "redis://localhost:7776"

require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"
require "minitest"
require "minitest/mock"
require "sidekiq/testing"
require "webmock/minitest"

require "support/login_helper"
require "support/factory_helper"
require "support/assertions"
require "support/api_controller_test_case"
require "support/push_server_mock"

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = "./test/fixtures/stripe_webhooks/"
WebMock.disable_net_connect!(allow_localhost: true, allow: "codeclimate.com")

redis_test_instance = IO.popen("redis-server --port 7776")
Minitest.after_run do
  Process.kill("INT", redis_test_instance.pid)
end

$redis = {
  entries: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) },
  refresher: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) },
}

Capybara.register_driver(:headless_chrome) do |app|
  capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
    chromeOptions: {args: ["headless", "disable-gpu", "window-size=1340,800"]},
  )

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    desired_capabilities: capabilities,
  )
end

Capybara.default_max_wait_time = 10

class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper

  fixtures :all

  def raw_post(action, params, body)
    @request.env["RAW_POST_DATA"] = body
    response = post(action, params: params)
    @request.env.delete("RAW_POST_DATA")
    response
  end

  def flush_redis
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

  def stub_request_file(file, url, response_options = {})
    file = File.join(Rails.root, "test/support/www", file)
    options = {body: File.new(file), status: 200}.merge(response_options)
    stub_request(:get, url).
      to_return(options)
  end

  def load_tweet
    file = File.join(Rails.root, "test/support/tweet_one.json")
    JSON.parse(File.read(file))
  end

  def create_stripe_plan(plan)
    Stripe::Plan.create(name: plan.name, id: plan.stripe_id, amount: plan.price.to_i, currency: "USD", interval: "day")
  end

  def clear_search
    begin
      Entry.__elasticsearch__.delete_index!
    rescue
      nil
    end
    begin
      Entry.__elasticsearch__.create_index!
    rescue
      nil
    end
  end
end
