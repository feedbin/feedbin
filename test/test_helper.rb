require "coveralls"
Coveralls.wear!("rails")

ENV["RAILS_ENV"] ||= "test"

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
Sidekiq.logger.level = Logger::WARN

unless ENV["CI"]
  socket = Socket.new(:INET, :STREAM, 0)
  socket.bind(Addrinfo.tcp("127.0.0.1", 0))
  port = socket.local_address.ip_port
  socket.close

  ENV["REDIS_URL"] = "redis://localhost:%d" % port
  redis_test_instance = IO.popen("redis-server --port %d --save '' --appendonly no" % port)

  Minitest.after_run do
    Process.kill("INT", redis_test_instance.pid)
  end
end

$redis = {
  entries: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) },
  refresher: ConnectionPool.new(size: 10) { Redis.new(url: ENV["REDIS_URL"]) }
}

class ActiveSupport::TestCase
  include LoginHelper
  include FactoryHelper

  fixtures :all

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

  def support_file(file)
    File.join(Rails.root, "test/support/www", file)
  end

  def stub_request_file(file, url, response_options = {})
    options = {body: File.new(support_file(file)), status: 200}.merge(response_options)
    stub_request(:get, url)
      .to_return(options)
  end

  def load_tweet(option)
    JSON.parse(File.read(support_file("tweet_#{option}.json")))
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

  def newsletter_params(recipient, signature, title = nil, from = nil)
    title = SecureRandom.hex if title.nil?
    {
      "timestamp" => "timestamp",
      "token" => "token",
      "signature" => signature,
      "recipient" => "#{recipient}@development.newsletters.feedbin.com",
      "sender" => "#{title}@feedbin.com",
      "subject" => "#{title} This is the subject",
      "from" => "#{title} <#{from || "ben"}@feedbin.com>",
      "X-Mailgun-Incoming" => "Yes",
      "X-Envelope-From" => "<ben@feedbin.com>",
      "Received" => "XYZ",
      "Dkim-Signature" => "XYZ",
      "X-Google-Dkim-Signature" => "XYZ",
      "X-Gm-Message-State" => "XYZ",
      "X-Received" => "XYZ",
      "Return-Path" => "<ben@feedbin.com>",
      "From" => "Ben Ubois <#{title}@feedbin.com>",
      "Content-Type" => "multipart/alternative; boundary=\"Apple-Mail=_8AB713F4-14C8-48B5-AD4B-B694CA436A93\"",
      "Subject" => "This is the subject",
      "Message-Id" => "<0B507DA2-3174-4575-8987-C2064F3D532C@feedbin.com>",
      "Date" => "Thu, 28 Jul 2016 18:44:38 -0700",
      "To" => "#{recipient}@development.newsletters.feedbin.com",
      "Mime-Version" => "1.0 (Mac OS X Mail 9.3 \\(3124\\))",
      "X-Mailer" => "Apple Mail (2.3124)",
      "message-headers" => "XYZ",
      "body-plain" => "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation .",
      "body-html" => "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html charset=us-ascii\"></head><body style=\"word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space;\" class=\"\"><div style=\"margin: 0px; line-height: normal;\" class=\"\"><b class=\"\">Lorem ipsum</b> dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.</div></body></html>",
      "stripped-html" => "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html charset=us-ascii\"></head><body style=\"word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space;\" class=\"\"><div style=\"margin: 0px; line-height: normal;\" class=\"\"><b class=\"\">Lorem ipsum</b> dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.</div></body></html>",
      "stripped-text" => "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation .",
      "stripped-signature" => "",
      "List-Unsubscribe" => "<http://www.host.com/list.cgi?cmd=unsub&lst=list>, <mailto:list-request@host.com?subject=unsubscribe>"
    }
  end
end
