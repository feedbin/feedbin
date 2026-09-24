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
previews are most of the rows, and a batch rewrites a row only when its
mapped kind differs from what is stored. `updated_at` is a view cache key
and the job does not touch it, so no caches move.

The schedule step pushes one job per 5,000 ids onto the `utility` queue at
once, the same fan-out `BackfillProviderIds` and `UpdateDefaultColumn` use.
At 63,157,053 rows that is about 12,632 jobs. Each is one indexed id-range
scan plus at most four `UPDATE` statements on that range. Measured locally
on 2,000,000 rows, one batch took under a third of a second and rewrote
3,125 rows; production has a smaller share of non-poster rows, so expect
less. The wall clock is the sum of the batches divided by the `utility`
concurrency, so roughly an hour of single-worker time spread across the
workers. Other `utility` jobs queue behind the fan-out until it drains.

A batch stops with an error if it holds a preset outside the map or a row
with no preset. That should not happen; if it does, the error names the
presets and the id range, and the other batches keep going.

## Trial

```ruby
# How many rows the run has to look at, and how many it will rewrite.
puts Image.count
puts Image.where.not(kind: :poster).count

preset = Image.data_projection("preset")
puts Image.where(preset.not_in(BackfillImageKinds::PRESET_KINDS.keys).or(preset.eq(nil))).count

# Trial: the batch that holds the lowest id, run inline. Batches number
# ids in blocks of SidekiqHelper::BATCH_SIZE, starting at 1.
batch = ((Image.minimum(:id) - 1) / SidekiqHelper::BATCH_SIZE) + 1
puts batch
BackfillImageKinds.new.perform(batch)

# The rows in that batch, by kind.
ids = BackfillImageKinds.new.build_ids(batch)
puts Image.where(id: ids.first..ids.last).group(:kind).count.inspect
```

## Full run

```ruby
BackfillImageKinds.perform_async(nil, true)
```

The schedule job pushes every batch. Watch the `utility` queue and the
`BackfillImageKinds:` log lines, which carry `batch` and `updated`. The run
is over when the queue has no `BackfillImageKinds` jobs.

To rerun after an interruption or a failed batch, schedule again. Reruns
are safe: a row already at its mapped kind is skipped, so a repeated batch
costs a scan and nothing else. To rerun one failed batch, take the batch
number from its error and call `BackfillImageKinds.perform_async(batch)`.
`feed_icon`, `micropost_avatar` and `icon` are self-labeled
(`BackfillImageKinds::SELF_LABELED`): their rows already carry their kind
from the call site, so a rerun skips them rather than treating the preset
as unmapped.

## Done

```ruby
puts Image.group(:kind).count.inspect
preset = Image.data_projection("preset")
BackfillImageKinds::PRESET_KINDS.group_by { |_, kind| kind }.each do |kind, pairs|
  puts "#{kind}: #{Image.where(preset.in(pairs.map(&:first))).where.not(kind: kind).count} rows still wrong"
end
```

Every line should end in `0 rows still wrong`.
