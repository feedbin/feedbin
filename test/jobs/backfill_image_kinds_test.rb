require "test_helper"

class BackfillImageKindsTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  # Every row since the table was recreated carries data->>'preset', and the
  # column default labels all of them poster until this runs.
  def row(preset, provider: :entry_preview, provider_id: SecureRandom.hex(4))
    create_image_row(provider: provider, provider_id: provider_id, data: {"preset" => preset})
  end

  # The batch that holds an id, in SidekiqHelper's numbering. Sequences do
  # not reset between tests, so the rows can straddle a batch boundary.
  def batches_for(*rows)
    rows.map { |record| ((record.id - 1) / SidekiqHelper::BATCH_SIZE) + 1 }.uniq
  end

  def perform_batches_for(*rows)
    batches_for(*rows).each { |batch| BackfillImageKinds.new.perform(batch) }
  end

  test "maps every preset to its kind" do
    expected = {
      "primary"        => :poster,
      "youtube"        => :poster,
      "twitter"        => :poster,
      "podcast"        => :cover_art,
      "podcast_feed"   => :cover_art,
      "channel_avatar" => :avatar,
      "favicon"        => :site_icon,
      "touch_icon"     => :site_icon
    }
    assert_equal expected, BackfillImageKinds::PRESET_KINDS

    rows = expected.keys.index_with { |preset| row(preset) }
    perform_batches_for(*rows.values)

    rows.each do |preset, record|
      assert_equal expected.fetch(preset).to_s, record.reload.kind, preset
    end
  end

  test "rewrites only rows whose kind is wrong" do
    right = row("primary")
    wrong = row("podcast")
    updated_at = 1.day.ago
    Image.where(id: [right.id, wrong.id]).update_all(updated_at: updated_at)

    perform_batches_for(right, wrong)

    assert_equal updated_at.to_i, right.reload.updated_at.to_i, "an already-correct row is not touched"
    assert_equal "cover_art", wrong.reload.kind
    # updated_at is a view cache key that moves only when the bytes move.
    assert_equal updated_at.to_i, wrong.updated_at.to_i
  end

  test "a batch touches only its own ids" do
    inside = row("podcast")
    batch = batches_for(inside).first

    BackfillImageKinds.new.perform(batch + 1)
    assert_equal "poster", inside.reload.kind

    BackfillImageKinds.new.perform(batch)
    assert_equal "cover_art", inside.reload.kind
  end

  # The fan-out: one job per batch of ids, pushed at once, drained by the
  # utility workers in parallel. No delay and no chain.
  test "schedule pushes one job per batch of ids" do
    first = row("podcast")
    last = row("favicon")

    BackfillImageKinds.new.perform(nil, true)

    expected = BackfillImageKinds.new.job_args(Image.maximum(:id), Image.minimum(:id))
    assert_equal expected, BackfillImageKinds.jobs.map { it["args"] }
    assert_includes BackfillImageKinds.jobs.map { it["args"].first }, batches_for(first).first
    assert_includes BackfillImageKinds.jobs.map { it["args"].first }, batches_for(last).first

    Sidekiq::Worker.drain_all

    assert_equal "cover_art", first.reload.kind
    assert_equal "site_icon", last.reload.kind
  end

  test "schedule with no rows pushes nothing" do
    Image.delete_all

    BackfillImageKinds.new.perform(nil, true)

    assert_empty BackfillImageKinds.jobs
  end

  # feed_icon rows carry their kind (avatar or site_icon) from the call
  # site, not from the preset, so the backfill must leave them alone rather
  # than treat the preset as unmapped.
  test "leaves self-labeled feed_icon rows alone" do
    feed_icon = create_image_row(provider: :entry_preview, provider_id: SecureRandom.hex(4), data: {"preset" => "feed_icon"}, kind: :avatar)

    perform_batches_for(feed_icon)

    assert_equal "avatar", feed_icon.reload.kind
  end

  # The avatar crawler and the copy backfill write their rows with the kind
  # set at the call site too, so a rerun after they run must accept them.
  test "leaves self-labeled micropost_avatar and icon rows alone" do
    micropost_avatar = create_image_row(provider: :entry_icon, provider_id: SecureRandom.hex(4), data: {"preset" => "micropost_avatar"}, kind: :avatar)
    copy = create_image_row(provider: :remote_file, provider_id: SecureRandom.hex(16), data: {"preset" => "icon"}, kind: :avatar)

    perform_batches_for(micropost_avatar, copy)

    assert_equal "avatar", micropost_avatar.reload.kind
    assert_equal "avatar", copy.reload.kind
  end

  # Nothing since the recreate should be unclassifiable. If a row is, the
  # batch must say so rather than leave the default in place silently.
  test "raises on a preset outside the map" do
    mystery = row("mystery")

    error = assert_raises(RuntimeError) { perform_batches_for(mystery) }
    assert_match(/mystery/, error.message)
  end
end
