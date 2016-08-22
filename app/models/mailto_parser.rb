class MailtoParser

  attr_reader :mailto

  def initialize(mailto)
    @mailto = mailto
  end

  def email
    parsed.path
  end

  def params
    parsed.query_values || {}
  end

  private

  def parsed
    @parsed ||= Addressable::URI.parse(mailto)
  end

end