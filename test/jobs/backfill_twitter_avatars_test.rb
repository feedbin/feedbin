require "test_helper"

class BackfillTwitterAvatarsTest < ActiveSupport::TestCase
  setup do
    flush_redis
  end

  test "twitter_rows holds both Twitter hosts on either scheme and nothing else" do
    kept = [
      remote_file("https://pbs.twimg.com/profile_images/1/a.jpg"),
      remote_file("http://pbs.twimg.com/profile_images/2/b.jpg"),
      remote_file("https://abs.twimg.com/sticky/default_profile_images/default_profile.png"),
      remote_file("http://abs.twimg.com/sticky/default_profile_images/default_profile_2.png")
    ]
    remote_file("https://micro.blog/someone/avatar.jpg")
    remote_file("https://pbs.twimg.com.evil.example/profile_images/3/c.jpg")

    assert_equal kept.map(&:id).sort, BackfillTwitterAvatars.twitter_rows.pluck(:id).sort
  end

  test "pending leaves out a row that already has its twitter_avatar image" do
    copied = remote_file("https://pbs.twimg.com/profile_images/1/a.jpg")
    waiting = remote_file("https://pbs.twimg.com/profile_images/2/b.jpg")
    create_image_row(provider: :twitter_avatar, provider_id: TwitterAvatar.fingerprint(copied.original_url), feed_id: nil, kind: :avatar, url: copied.original_url, variant: "400x400")

    assert_equal [waiting.id], BackfillTwitterAvatars.pending.pluck(:id)
  end

  # NOT IN is never planned as an anti-join; the LEFT JOIN is.
  test "pending is an anti-join" do
    sql = BackfillTwitterAvatars.pending.to_sql

    assert_includes sql, "LEFT OUTER JOIN"
    refute_includes sql, "NOT IN"
  end

  test "batch_for and batch_range agree" do
    assert_equal 1, BackfillTwitterAvatars.batch_for(1)
    assert_equal 1, BackfillTwitterAvatars.batch_for(250)
    assert_equal 2, BackfillTwitterAvatars.batch_for(251)
    assert_equal 251..500, BackfillTwitterAvatars.batch_range(2)
  end

  test "the kickoff pushes one job per batch from the first id to the last" do
    remote_file("https://pbs.twimg.com/profile_images/1/a.jpg", id: 1_000_001)
    remote_file("https://pbs.twimg.com/profile_images/2/b.jpg", id: 1_000_600)

    BackfillTwitterAvatars.new.perform(nil, true)

    first = BackfillTwitterAvatars.batch_for(1_000_001)
    last = BackfillTwitterAvatars.batch_for(1_000_600)
    assert_equal (first..last).zip, BackfillTwitterAvatars.jobs.map { it["args"] }
  end

  test "the kickoff on an empty table pushes nothing" do
    RemoteFile.delete_all

    BackfillTwitterAvatars.new.perform(nil, true)

    assert_empty BackfillTwitterAvatars.jobs
  end

  private

  def remote_file(url, storage_url: "https://icons.example.net/#{SecureRandom.hex}.jpg", **attributes)
    RemoteFile.create!(fingerprint: RemoteFile.fingerprint(url), original_url: url, storage_url: storage_url, **attributes)
  end
end
