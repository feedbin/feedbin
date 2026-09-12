# Image kind backfill

Deploy the `images.kind` migration and `BackfillImageKinds` together, then
run these production Rails console commands. Run the backfill before
anything reads `kind`: until it finishes, every pre-migration row reads as
`poster`, which is the column default.

`kind` says what a picture is (`cover_art`, `avatar`, `site_icon`,
`poster`). `provider` keeps its separate job as the key that addresses the
row. The crawler sets `kind` at each call site from now on. For rows written
before the column existed, the only record of what the crawler knew is
`data->>'preset'`, and every row since the 2026-08 recreate carries one.
`BackfillImageKinds::PRESET_KINDS` is that map.

## What the run costs

Read-only for most of the table. The default is `poster` because entry
previews are most of the rows, and the job rewrites a row only when its
mapped kind differs from what is stored. `updated_at` is a view cache key
and the job does not touch it, so no caches move.

Each batch is one indexed id-range scan plus at most four `UPDATE`
statements on that range. Measured locally on 2,000,000 rows: one batch of
5,000 took under a third of a second and rewrote 3,125 rows. Production has
a smaller share of non-poster rows, so expect less. Batches run on the
`utility` queue with a one second gap by default.

The job stops with an error if a batch holds a preset outside the map or a
row with no preset. That should not happen; if it does, the error names the
presets and the id range.

## Trial

```ruby
# How many rows the run has to look at, and how many it will rewrite.
puts Image.count
puts Image.where.not(kind: :poster).count

preset = Image.data_projection("preset")
puts Image.where(preset.not_in(BackfillImageKinds::PRESET_KINDS.keys).or(preset.eq(nil))).count

# Trial: one batch over the first 1,000 ids, no follow-up job.
trial_finish = Image.where(Image.arel_table[:id].lteq(Image.minimum(:id) + 999)).maximum(:id)
puts trial_finish
BackfillImageKinds.new.perform(0, trial_finish, 1_000, 0)

# The rewritten rows in that range, by kind.
puts Image.where(Image.arel_table[:id].lteq(trial_finish)).group(:kind).count.inspect
```

## Full run

```ruby
# finish_id freezes the upper bound. Rows inserted after the migration
# already carry their kind, so the run does not need to reach them.
finish_id = Image.maximum(:id)
puts finish_id
$redis[:refresher].with { |redis| redis.set("backfill_image_kinds:finish_id", finish_id) }

BackfillImageKinds.perform_async(0, finish_id)
```

Batches chain through Sidekiq. Watch the `utility` queue and the
`BackfillImageKinds:` log lines, which carry `scanned`, `updated`,
`last_id`, and `finish_id`. The run is over when the log's `last_id` reaches
`finish_id` and the queue has no `BackfillImageKinds` jobs.

To resume an interrupted run, take the last logged `last_id` and the stored
`finish_id`:

```ruby
finish_id = $redis[:refresher].with { |redis| redis.get("backfill_image_kinds:finish_id") }.to_i
puts finish_id
# last_id: copy it from the most recent "BackfillImageKinds:" log line.
```

Then call `BackfillImageKinds.perform_async(last_id, finish_id)` with that
value. Reruns are safe: a row already at its mapped kind is skipped.

## Slower or faster

The third and fourth arguments are batch size and the delay in seconds
between batches. To restart at half speed without a deploy:

```ruby
BackfillImageKinds.perform_async(last_id, finish_id, 2_500, 2)
```

## Done

```ruby
puts Image.where(Image.arel_table[:id].lteq(finish_id)).group(:kind).count.inspect
preset = Image.data_projection("preset")
BackfillImageKinds::PRESET_KINDS.group_by { |_, kind| kind }.each do |kind, pairs|
  puts "#{kind}: #{Image.where(preset.in(pairs.map(&:first))).where.not(kind: kind).count} rows still wrong"
end
```

Every line should end in `0 rows still wrong`.
