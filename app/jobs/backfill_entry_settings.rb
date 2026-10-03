# Cleans entries.settings and newsletter entries.data in place: settings
# becomes a jsonb object without the keys nothing reads, the Mailgun-era
# sender moves into newsletter_from, and newsletter data loses
# newsletter_text and the Mailgun payload. One job for each range of ids:
# production ids are sparse (about 2.6% in use), so the range is larger than
# SidekiqHelper::BATCH_SIZE.
class BackfillEntrySettings
  include Sidekiq::Worker

  sidekiq_options queue: :utility

  BATCH_SIZE = 100_000
  # Production cancels a statement after 15 s, and an app write that waits on
  # a row lock after 10 s. Each statement covers at most this many ids, so a
  # dense range of newsletter rows stays well inside both limits.
  SUB_RANGE = 5_000
  NUL_ESCAPE = "\\u0000"
  DELETED_SETTINGS_KEYS = %w[newsletter media_image].freeze
  DELETED_NEWSLETTER_DATA_KEYS = %w[newsletter newsletter_text].freeze

  # Newsletter rows. Each new value comes from the row itself, so if the app
  # changed the row first, Postgres computes it again from the newest
  # version. Rows with a \u0000 escape cannot be cast and are left for repair.
  NEWSLETTER_SQL = <<~SQL
    UPDATE entries
    SET settings = NULLIF(
          (COALESCE(NULLIF(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, 'null'::jsonb), '{}'::jsonb)
            - ARRAY['newsletter', 'media_image'])
          || CASE
            WHEN entries.data -> 'newsletter' -> 'data' ->> 'from' IS NULL THEN '{}'::jsonb
            WHEN COALESCE(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, '{}'::jsonb) ? 'newsletter_from' THEN '{}'::jsonb
            ELSE jsonb_build_object('newsletter_from', entries.data -> 'newsletter' -> 'data' ->> 'from')
          END,
          '{}'::jsonb),
        data = (entries.data::jsonb - ARRAY['newsletter', 'newsletter_text'])::json
    WHERE entries.id BETWEEN $1 AND $2
      AND EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3)
      AND CASE
        WHEN strpos(COALESCE(entries.settings #>> '{}', ''), $4) > 0 THEN false
        WHEN strpos(COALESCE(entries.data::text, ''), $4) > 0 THEN false
        ELSE jsonb_typeof(entries.settings) = 'string'
          OR entries.settings ?| ARRAY['newsletter', 'media_image']
          OR entries.data::jsonb ?| ARRAY['newsletter', 'newsletter_text']
      END
  SQL

  # Every other row: unwrap the JSON string into an object, without the
  # deleted keys.
  OTHER_SQL = <<~SQL
    UPDATE entries
    SET settings = NULLIF(
          NULLIF(CASE jsonb_typeof(entries.settings) WHEN 'string' THEN (entries.settings #>> '{}')::jsonb ELSE entries.settings END, 'null'::jsonb)
            - ARRAY['newsletter', 'media_image'],
          '{}'::jsonb)
    WHERE entries.id BETWEEN $1 AND $2
      AND NOT EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3)
      AND CASE
        WHEN entries.settings IS NULL THEN false
        WHEN strpos(entries.settings #>> '{}', $4) > 0 THEN false
        ELSE jsonb_typeof(entries.settings) = 'string'
          OR entries.settings ?| ARRAY['newsletter', 'media_image']
      END
  SQL

  NUL_ROWS_SQL = <<~SQL
    SELECT entries.id FROM entries
    WHERE entries.id BETWEEN $1 AND $2
      AND (
        strpos(COALESCE(entries.settings #>> '{}', ''), $4) > 0
        OR (strpos(COALESCE(entries.data::text, ''), $4) > 0
          AND EXISTS (SELECT 1 FROM feeds WHERE feeds.id = entries.feed_id AND feeds.feed_type = $3))
      )
  SQL

  NUL_ROW_SQL = <<~SQL
    SELECT entries.settings, entries.data, feeds.feed_type
    FROM entries LEFT JOIN feeds ON feeds.id = entries.feed_id
    WHERE entries.id = $1
    FOR UPDATE OF entries
  SQL

  def perform(batch)
    # exec_update does not clear the query cache, and Sidekiq runs jobs inside
    # the Rails executor, where the cache is on.
    Entry.uncached do
      last = batch * BATCH_SIZE
      ((batch - 1) * BATCH_SIZE + 1).step(last, SUB_RANGE) do |first|
        binds = [first, [first + SUB_RANGE - 1, last].min, newsletter_type, NUL_ESCAPE]
        connection.exec_update(NEWSLETTER_SQL, "BackfillEntrySettings newsletter", binds)
        connection.exec_update(OTHER_SQL, "BackfillEntrySettings other", binds)
        connection.select_values(NUL_ROWS_SQL, "BackfillEntrySettings NUL rows", binds).each { repair(it) }
      end
    end
  end

  def build
    batches = (Entry.maximum(:id) / BATCH_SIZE.to_f).ceil
    Sidekiq::Client.push_bulk(
      "args" => (1..batches).each_slice(1).to_a,
      "class" => self.class
    )
  end

  private

  # Postgres cannot parse these rows, so Ruby does: it parses \u0000 into a
  # NUL character, which jsonb cannot store, so the NUL goes too.
  def repair(id)
    Entry.transaction do
      row = connection.select_one(NUL_ROW_SQL, "BackfillEntrySettings NUL row", [id])
      settings = row["settings"] && JSON.parse(row["settings"])
      settings = JSON.parse(settings) if settings.is_a?(String)
      settings = without_nul((settings || {}).except(*DELETED_SETTINGS_KEYS))
      if row["feed_type"] == newsletter_type
        data = row["data"] ? JSON.parse(row["data"]) : {}
        from = data.dig("newsletter", "data", "from")
        settings["newsletter_from"] ||= from.delete("\0") if from
        data = without_nul(data.except(*DELETED_NEWSLETTER_DATA_KEYS))
        connection.exec_update("UPDATE entries SET settings = $1::jsonb, data = $2::json WHERE id = $3", "BackfillEntrySettings repair",
          [(JSON.generate(settings) if settings.any?), JSON.generate(data), id])
      else
        connection.exec_update("UPDATE entries SET settings = $1::jsonb WHERE id = $2", "BackfillEntrySettings repair",
          [(JSON.generate(settings) if settings.any?), id])
      end
    end
  end

  def without_nul(hash)
    hash.transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end

  def newsletter_type
    Feed.feed_types.fetch("newsletter")
  end

  def connection
    Entry.connection
  end
end
