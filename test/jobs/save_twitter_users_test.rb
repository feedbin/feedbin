require "test_helper"

class SaveTwitterUsersTest < ActiveSupport::TestCase
  setup do
    @user = users(:new)
    @feed = create_feeds(@user, 1).first
    @entry = create_tweet_entry(@feed)
    @screen_name = @entry.tweet.main_tweet.user.screen_name
  end

  test "stores the author of the tweet" do
    SaveTwitterUsers.new.perform(@entry.id)

    author = TwitterUser.where_lower(screen_name: @screen_name).take
    assert_not_nil author
    assert_equal @screen_name, author.data["screen_name"]
  end

  test "refreshes an author that is already stored" do
    TwitterUser.create!(screen_name: @screen_name, data: {"screen_name" => @screen_name, "name" => "stale"})

    assert_no_difference -> { TwitterUser.where_lower(screen_name: @screen_name).count } do
      SaveTwitterUsers.new.perform(@entry.id)
    end
    assert_not_equal "stale", TwitterUser.where_lower(screen_name: @screen_name).take.data["name"]
  end

  test "recovers when a concurrent worker stores the same author first" do
    # Every entry quoting or replying to an author races for that author's row,
    # and index_twitter_users_on_lower_screen_name is on lower(screen_name), so
    # the winner's differing letter case still collides with our INSERT.
    @committed_screen_name = @screen_name
    screen_name = @screen_name

    outside_transaction do |other_worker|
      raced = false
      race_winner = ->(_record) do
        next if raced
        raced = true
        other_worker.execute(<<~SQL, screen_name.upcase)
          INSERT INTO twitter_users (screen_name, data, created_at, updated_at)
          VALUES (?, '{}', now(), now())
        SQL
      end
      TwitterUser.set_callback(:create, :before, race_winner)

      begin
        SaveTwitterUsers.new.perform(@entry.id)
        assert raced, "the race was never triggered"

        author = TwitterUser.where_lower(screen_name: screen_name).take
        assert_equal screen_name, author.data["screen_name"], "the winner's row should still get the profile"
      ensure
        TwitterUser.skip_callback(:create, :before, race_winner)
      end
    end
  end

  # Runs after the fixture transaction has rolled back, so the DELETE does not
  # wait on rows this test left uncommitted.
  def after_teardown
    super
    return unless @committed_screen_name
    outside_transaction do |connection|
      connection.execute("DELETE FROM twitter_users WHERE lower(screen_name) = lower(?)", @committed_screen_name)
    end
  end
end
