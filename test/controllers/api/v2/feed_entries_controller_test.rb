require 'test_helper'

class Api::V2::FeedEntriesControllerTest < ApiControllerTestCase

  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
  end


end
