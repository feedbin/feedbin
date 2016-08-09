require 'minitest/assertions'

module Feedbin
  module Assertions

    def assert_has_keys(keys, hash)
      assert(keys.all?{|key| hash.key?(key) })
    end

  end
end