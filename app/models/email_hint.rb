# An address shown to someone who may not own it: enough to recognise, not
# enough to learn. "ben@example.com" => "b•••@example.com".
class EmailHint
  def initialize(email)
    @local, @domain = email.to_s.split("@", 2)
  end

  def to_s
    [@local.to_s[0], "•••", ("@#{@domain}" if @domain)].join
  end
end
