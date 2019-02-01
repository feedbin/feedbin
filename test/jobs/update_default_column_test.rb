require "test_helper"

class UpdateDefaultColumnTest < ActiveSupport::TestCase
  setup do
    UpdateDefaultColumn.jobs.clear
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @args = {
      "klass" => "Entry",
      "column" => "title",
      "default" => SecureRandom.hex,
      "schedule" => true,
    }
  end

  test "should enqueue jobs" do
    UpdateDefaultColumn.new.perform(@args)
    assert_equal([["schedule", true]], (@args.to_a - UpdateDefaultColumn.jobs.first["args"].first.to_a))
  end

  test "should set new default jobs" do
    Sidekiq::Testing.inline! do
      UpdateDefaultColumn.perform_async(@args)
    end

    assert_equal([@args["default"]], Entry.all.pluck(:title).uniq)
  end
end
