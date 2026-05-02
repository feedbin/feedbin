require "test_helper"

class FeedFixerSchedulerTest < ActiveSupport::TestCase
  test "delegates to FeedFixer#build" do
    called = false
    original_build = FeedFixer.instance_method(:build)
    FeedFixer.define_method(:build) { called = true }
    begin
      FeedFixerScheduler.new.perform
    ensure
      FeedFixer.define_method(:build, original_build)
    end
    assert called
  end
end
