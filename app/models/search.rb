module Search
  def self.index_name(base_name)
    Rails.env.test? ? "test-#{base_name}" : base_name
  end
end
