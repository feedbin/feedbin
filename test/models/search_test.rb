require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "prefixes the base name in the test environment" do
    assert_equal "test-entries", Search.index_name("entries")
  end

  test "returns the base name unchanged outside the test environment" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_equal "entries", Search.index_name("entries")
    end
  end
end
