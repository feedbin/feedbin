class MailtoParser
  attr_reader :mailto

  def initialize(mailto)
    @mailto = mailto
  end

  def email
    parsed.path
  end

  def body
    params["body"]
  end

  def subject
    params["subject"]
  end

  private

  def params
    @params ||= parsed.query_values || {}
  end

  def parsed
    @parsed ||= Addressable::URI.parse(mailto)
  end
end
