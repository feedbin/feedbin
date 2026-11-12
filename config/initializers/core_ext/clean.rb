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
  # What an HTML parser acts on in text, or drops from it: markup, character
  # references, NUL and the C0 controls other than tab, newline and carriage
  # return, U+FFFE and U+FFFF.
  HTML_PARSER_CHARACTERS = /[<&\x00-\x08\x0B\x0C\x0E-\x1F\u{FFFE}\u{FFFF}]/

  # Sizes the parser returns whole and as UTF-8: its empty string is
  # US-ASCII, and libxml2 cuts text off near 10 MB.
  HTML_PARSER_WHOLE_BYTES = (1..1.megabyte)

  # Most of what this is called on (a title, an author) has no HTML in it,
  # and parsing it costs about twenty times what the rest of this does. Text
  # with nothing in it for the parser comes back from the parser unchanged,
  # so it skips the parse; anything else, an invalid or non-UTF-8 string
  # included, is parsed as before. test/lib/string_to_plain_text_test.rb
  # holds the two answers together.
  def to_plain_text
    plain = encoding == Encoding::UTF_8 && HTML_PARSER_WHOLE_BYTES.cover?(bytesize) && valid_encoding? && !match?(HTML_PARSER_CHARACTERS)
    text = plain ? self : Loofah.fragment(self).scrub!(:prune).to_text(encode_special_chars: false)
    text.gsub(/\s+/, " ").strip
  end
end