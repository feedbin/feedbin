require "test_helper"

class ActionTagsTest < ActiveSupport::TestCase
  test "updates tag ids" do
    action = actions(:api)
    user = action.user
    old_tag_id = action.tag_ids.sample
    tag = user.feeds.first.tag(SecureRandom.hex, user).first.tag

    ActionTags.new.perform(user.id, tag.id, old_tag_id)

    assert action.reload.tag_ids.include? tag.id
  end
end
