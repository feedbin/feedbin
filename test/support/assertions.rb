require "minitest/assertions"

module Feedbin
  module Assertions
    def assert_has_keys(keys, hash)
      assert(keys.all? { |key| hash.key?(key) })
    end

    def assert_equal_ids(collection, results)
      expected = Set.new(collection.map(&:id))
      actual = Set.new(results.map { |result| result["id"] })
      assert_equal(expected, actual)
    end
  end
end
