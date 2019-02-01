require "test_helper"

class SelfUrlTest < ActiveSupport::TestCase
  # test "should build" do
  #   assert_difference "Sidekiq::Queues['worker_slow'].count", +Feed.count do
  #     SelfUrl.new().perform(nil, true)
  #   end
  # end
  #
  # test "should add self_url" do
  #   feed = feeds(:daring_fireball)
  #   self_url = Faker::Internet.url
  #
  #   body = <<-eot
  #   <?xml version="1.0" encoding="utf-8"?>
  #   <feed xmlns="http://www.w3.org/2005/Atom">
  #       <link href="#{self_url}" rel="self" />
  #   </feed>
  #   eot
  #
  #   stub_request(:get, feed.feed_url).
  #     to_return(body: body, status: 200)
  #
  #   SelfUrl.new().perform(feed.id)
  #
  #   assert_equal self_url, feed.reload.self_url
  # end
end
