require "test_helper"

class ActionTest < ActiveSupport::TestCase
  def setup
    @user = users(:ben)
    @action = actions(:ben_one)
  end

  test "should be valid" do
    assert @action.valid?
  end

  test "feeds should be present" do
    action = @user.actions.build(feed_ids: [])
    assert_not action.valid?
  end

  test "must be subscribed to requested feeds" do
    feed = Feed.create
    action = @user.actions.build(feed_ids: [feed.id])
    assert_not action.computed_feed_ids.include?(feed.id)
    assert_not action.valid?
  end

  test "must save to elasticsearch" do
    feed = feeds(:daring_fireball)
    action = Sidekiq::Testing.inline! {
      @user.actions.create(feed_ids: [feed.id])
    }
    assert percolator_found?(action)
  end

  test "recognizes tags" do
    feed = feeds(:daring_fireball)
    tagging = feed.tag("Favs", @user, false).first
    action = @user.actions.create(tag_ids: [tagging.tag.id])
    assert action.computed_feed_ids.include?(feed.id)
  end

  test "doesn't percolate when empty" do
    feed = feeds(:daring_fireball)
    action = Sidekiq::Testing.inline! {
      @user.actions.create(feed_ids: [feed.id])
    }
    assert percolator_found?(action)
    action.automatic_modification = true
    Sidekiq::Testing.inline! do
      action.update(feed_ids: [])
    end
    assert_not percolator_found?(action)
  end

  test "doesn't percolate when empty iOS" do
    action = Sidekiq::Testing.inline! {
      @user.actions.create(query: "hello", all_feeds: true, action_type: :notifier)
    }
    assert percolator_found?(action)
    Sidekiq::Testing.inline! do
      action.update(query: "")
    end
    assert_not percolator_found?(action)
  end

  test "enqueues PercolateDestroy when a destroy commits" do
    Sidekiq::Worker.clear_all
    ActiveRecord::Base.transaction do
      @action.destroy
    end
    assert_equal 1, Search::PercolateDestroy.jobs.size
  end

  test "does not enqueue PercolateDestroy when a destroy is rolled back" do
    Sidekiq::Worker.clear_all
    ActiveRecord::Base.transaction do
      @action.destroy
      raise ActiveRecord::Rollback
    end

    assert Action.exists?(@action.id), "the destroy should have rolled back"
    assert_empty Search::PercolateDestroy.jobs,
      "the percolator should not be removed for an action that still exists"
  end

  private

  def percolator_found?(action)
    action._percolator && action._percolator["found"] == true
  end
end
