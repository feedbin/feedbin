class CrawlDataType < ActiveModel::Type::Value
  def type
    :jsonb
  end

  def cast(value)
    if CrawlData === value
      value
    else
      CrawlData.new(value)
    end
  end

  def deserialize(value)
    if String === value
      decoded = ::ActiveSupport::JSON.decode(value) rescue nil
      CrawlData.new(decoded) unless decoded.nil?
    else
      super
    end
  end

  def serialize(value)
    case value
    when Array, Hash
      ::ActiveSupport::JSON.encode(value)
    when CrawlData
      ::ActiveSupport::JSON.encode(value.to_h)
    else
      super
    end
  end

  def changed_in_place?(raw_old_value, new_value)
    raw_old_value != serialize(new_value) if new_value.is_a?(::CrawlData)
  end
end