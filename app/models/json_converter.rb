class JsonConverter
  def self.dump(value)
    value.is_a?(String) ? JSON.load(value) : value
  end

  def self.load(value)
    value.is_a?(String) ? JSON.load(value) : value
  end
end