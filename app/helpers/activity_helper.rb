module ActivityHelper
  def first_of_value(value)
    value.is_a?(Array) ? value.first : value
  end

  def value_or_id(value)
    value.is_a?(String) || value.nil? ? value : value["id"]
  end
end
