# TypeError is thrown if the key exists but doesn't respond to dig
# i.e {key: "value"}.dig(:key, :key2)

class Hash
  def safe_dig(*args)
    dig(*args)
  rescue TypeError
    nil
  end
end

class Array
  def safe_dig(*args)
    dig(*args)
  rescue TypeError
    nil
  end
end
