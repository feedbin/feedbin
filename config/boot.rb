ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

Fixnum = Integer
Bignum = Integer

class File
  class << self
    alias_method :exists?, :exist?
  end
end

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
