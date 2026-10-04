# Entry#settings is jsonb, but from 2019 to 2026 a JSON coder wrapped it, so
# old rows held the hash as a JSON string inside jsonb. load reads both forms.
# dump writes a real object. A jsonb object cannot hold NUL, so dump removes
# it from string values.
class EntrySettingsCoder
  def self.load(value)
    value.is_a?(String) ? (JSON.parse(value) if value.present?) : value
  end

  def self.dump(value)
    value.transform_values { it.is_a?(String) ? it.delete("\0") : it }
  end
end
