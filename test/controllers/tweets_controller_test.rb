require "test_helper"
require "minitest/stub_any_instance"

class TweetsControllerTest < ActionController::TestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
  end

  test "should get thread" do
    login_as @user
    entry = create_tweet_entry(@user.feeds.first)

    client = Client.new
    TweetsController.stub_any_instance :client, client do
      get :thread, params: {id: entry}, xhr: true
    end

    assert_response :success
  end

  class Client
    def search(*args)
      ClientMethods.new
    end

    def user_timeline(*args)
      []
    end
  end

  class ClientMethods
    def take(*args)
      []
    end

    def to_h
      {search_metadata: {max_id: 1}}
    end
  end
end
