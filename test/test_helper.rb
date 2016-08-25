require 'codeclimate-test-reporter'
CodeClimate::TestReporter.start

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'minitest/autorun'
require 'sidekiq/testing'
require 'webmock/minitest'

require 'support/login_helper'
require 'support/factory_helper'
require 'support/assertions'
require 'support/dummy_server'
require 'support/api_controller_test_case'

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = './test/fixtures/stripe_webhooks/'
WebMock.disable_net_connect!(allow_localhost: true, allow: 'codeclimate.com')

redis_test_instance = IO.popen("redis-server --port 7776")
Minitest.after_run {
  Process.kill("INT", redis_test_instance.pid)
}

ENV['REDIS_URL'] = "redis://localhost:7776"
$redis = {
  sorted_entries: Redis.new(url: ENV['REDIS_URL']),
  id_cache: Redis.new(url: ENV['REDIS_URL'])
}

Entry.__elasticsearch__.delete_index! rescue nil
Entry.__elasticsearch__.create_index! rescue nil

class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper

  fixtures :all

  def raw_post(action, params, body)
    @request.env['RAW_POST_DATA'] = body
    response = post(action, params)
    @request.env.delete('RAW_POST_DATA')
    response
  end

  def flush_redis
    Sidekiq.redis do |redis|
      redis.flushdb
    end
    $redis.each do |_, redis|
      redis.flushdb
    end
  end

  def parse_json
    JSON.parse(@response.body)
  end

  def stub_request_file(file, url)
    file = File.join(Rails.root, 'test/support/www', file)
    stub_request(:get, url).
      to_return(body: File.new(file), status: 200)
  end

  def create_stripe_plan(plan)
    Stripe::Plan.create(name: plan.name, id: plan.stripe_id, amount: plan.price, currency: "USD", interval: "day")
  end
end
