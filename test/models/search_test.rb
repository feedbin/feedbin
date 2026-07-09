require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "prefixes the base name in the test environment" do
    with_test_worker(nil) do
      assert_equal "test-entries", Search.index_name("entries")
    end
  end

  test "includes the parallel worker number when TEST_WORKER is set" do
    with_test_worker("3") do
      assert_equal "test-3-entries", Search.index_name("entries")
    end
  end

  test "returns the base name unchanged outside the test environment" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_equal "entries", Search.index_name("entries")
    end
  end

  test "the search alias config is namespaced for the test environment" do
    prefix = ["test", ENV["TEST_WORKER"]].compact.join("-")
    assert_equal "#{prefix}-entries-01", $search[:config][:aliases][:entries]
    assert_equal "#{prefix}-actions-01", $search[:config][:aliases][:actions]
    assert_equal "#{prefix}-feeds-01", $search[:config][:aliases][:feeds]
  end

  private

  def with_test_worker(number)
    original = ENV["TEST_WORKER"]
    ENV["TEST_WORKER"] = number
    yield
  ensure
    original.nil? ? ENV.delete("TEST_WORKER") : ENV["TEST_WORKER"] = original
  end
end
