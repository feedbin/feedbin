class SmartSort
  SCAN = /[$-\/:-?{-~!"^_`\[\]]|[^\d\.]+|[\d\.]+/
  DIGITS = /\d+(\.\d+)?/
  SYMBOLS = /^[$-\/:-?{-~!"^_`\[\]]/

  attr_reader :value

  def initialize(value)
    @value = value
  end

  def <=>(other)
    other.is_a?(self.class) || raise("Sort error")
    left_value = value
    right_value = other.value
    if left_value.class == right_value.class
      left_value <=> right_value
    elsif left_value.is_a?(Float)
      -1
    else
      1
    end
  end

  def self.parse(string)
    string.scan(SCAN).collect do |atom|
      if atom.match?(SYMBOLS)
        ord = atom.ord
        atom = "-1.#{ord}".to_f
      elsif atom.match?(DIGITS)
        atom = atom.to_f
      else
        atom = normalize_string(atom)
      end
      new(atom)
    end
  end

  private

  def self.normalize_string(string)
    string = ActiveSupport::Inflector.transliterate(string)
    string.downcase
  end
end

String.class_eval do
  def to_sort_atoms
    SmartSort.parse(self)
  end
end

module Enumerable
  def natural_sort
    natural_sort_by
  end

  def natural_sort_by(&stringifier)
    sort_by do |element|
      element = yield(element) if stringifier
      element.to_s.to_sort_atoms
    end
  end
end
