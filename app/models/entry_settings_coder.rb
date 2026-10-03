# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows hold the hash as a JSON string inside jsonb. load reads both forms.
# dump drops the keys that nothing reads any more, and the NUL characters
# that a jsonb object cannot hold. Until every process can read objects, dump
# still writes the JSON string form.
class EntrySettingsCoder
  DELETED_KEYS = %w[newsletter media_image].freeze

  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    JSON.generate(value.except(*DELETED_KEYS).transform_values { it.is_a?(String) ? it.delete("\0") : it })
  end
end
