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
    BackfillImageKinds.new.perform

    rows.each do |preset, record|
      assert_equal expected.fetch(preset).to_s, record.reload.kind, preset
    end
  end

  test "rewrites only rows whose kind is wrong" do
    right = row("primary")
    wrong = row("podcast")
    updated_at = 1.day.ago
    Image.where(id: [right.id, wrong.id]).update_all(updated_at: updated_at)

    BackfillImageKinds.new.perform

    assert_equal updated_at.to_i, right.reload.updated_at.to_i, "an already-correct row is not touched"
    assert_equal "cover_art", wrong.reload.kind
    # updated_at is a view cache key that moves only when the bytes move.
    assert_equal updated_at.to_i, wrong.updated_at.to_i
  end

  test "walks the table in id batches and stops at the frozen upper bound" do
    first = row("podcast")
    second = row("podcast")
    third = row("podcast")

    BackfillImageKinds.new.perform(0, second.id, 1, 0)

    assert_equal "cover_art", first.reload.kind
    assert_equal "poster", second.reload.kind, "the batch was one row"
    assert_equal 1, BackfillImageKinds.jobs.size
    assert_equal [first.id, second.id, 1, 0], BackfillImageKinds.jobs.last["args"]

    Sidekiq::Worker.drain_all

    assert_equal "cover_art", second.reload.kind
    assert_equal "poster", third.reload.kind, "beyond finish_id"
    assert_empty BackfillImageKinds.jobs
  end

  # Nothing since the recreate should be unclassifiable. If a row is, the
  # run must say so rather than leave the default in place silently.
  test "raises on a preset outside the map" do
    row("mystery")

    error = assert_raises(RuntimeError) { BackfillImageKinds.new.perform }
    assert_match(/mystery/, error.message)
  end
end
