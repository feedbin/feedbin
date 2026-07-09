module Search
  def self.index_name(base_name)
    return base_name unless Rails.env.test?
    ["test", ENV["TEST_WORKER"], base_name].compact.join("-")
  end
end
