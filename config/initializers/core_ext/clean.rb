# frozen_string_literal: true

require "delegate"

module Cleanable #:nodoc:
  def clean(method_name = nil, default: nil, transform: nil)
    result = self
    if !method_name.nil?
      result = result.try(attribute)
    end
    return default if result.nil?
    transforms = [:strip].concat([*transform]).compact
    transforms.each do |transform|
      result = result.send(transform) if result.respond_to?(transform)
    end
    result = nil if result == ""
    result
  end
  ruby2_keywords(:clean)
end

class Object
  include Cleanable
end

class Delegator
  include Cleanable
end

class NilClass
  def clean(_method_name = nil, *)
    nil
  end
end

class String
  def to_text
    Loofah.fragment(self)
      .scrub!(:prune)
      .to_text(encode_special_chars: false)
      .gsub(/\s+/, " ")
      .strip
  end
end