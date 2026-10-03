# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows hold the hash as a JSON string inside jsonb. load reads both forms.
# dump writes a real object. A jsonb object cannot hold NUL, which the old
# string form could, so dump removes it. Until the backfill finishes, dump
# also drops the keys that nothing reads any more.
class EntrySettingsCoder
  DELETED_KEYS = %w[newsletter media_image].freeze

  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    value.except(*DELETED_KEYS).transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end
end
