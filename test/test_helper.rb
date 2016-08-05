require 'codeclimate-test-reporter'
CodeClimate::TestReporter.start

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'minitest/autorun'
require 'sidekiq/testing'
require 'webmock/minitest'

require 'login_helper'
require 'factory_helper'
require 'support/dummy_server'

ActiveRecord::FixtureSet.context_class.send :include, LoginHelper
StripeMock.webhook_fixture_path = './test/fixtures/stripe_webhooks/'
WebMock.disable_net_connect!(allow_localhost: true, allow: 'codeclimate.com')

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
    if Rails.env.test?
      $redis.each do |_, redis|
        redis.flushdb
      end
    end
  end
end
