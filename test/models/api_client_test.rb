require "test_helper"

class ApiClientTest < ActiveSupport::TestCase
  def page(ids)
    {
      body: {"feed_items" => ids.map { {"id" => _1} }}.to_json,
      headers: {"Content-Type" => "application/json"}
    }
  end

  test "feed_items_list honours a limit that is not a multiple of the page size" do
    stub_request(:get, /#{ENV["ACCOUNT_HOST"]}/).to_return(
      page(0...100),
      page(100...200),
      page([])
    )

    result = ApiClient.new("token").feed_items_list(params: {}, limit: 150)

    assert_equal 150, result.count
  end

  test "feed_items_list stops at a limit that is a multiple of the page size" do
    stub_request(:get, /#{ENV["ACCOUNT_HOST"]}/).to_return(
      page(0...100),
      page(100...200),
      page([])
    )

    result = ApiClient.new("token").feed_items_list(params: {}, limit: 100)

    assert_equal 100, result.count
  end

  test "feed_items_list returns everything when there is no limit" do
    stub_request(:get, /#{ENV["ACCOUNT_HOST"]}/).to_return(
      page(0...100),
      page([])
    )

    result = ApiClient.new("token").feed_items_list(params: {}, limit: nil)

    assert_equal 100, result.count
  end

  test "feed_items_list handles a response with no feed_items key" do
    stub_request(:get, /#{ENV["ACCOUNT_HOST"]}/).to_return(
      body: {}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    assert_equal [], ApiClient.new("token").feed_items_list(params: {}, limit: nil)
  end
end
