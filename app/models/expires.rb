class Expires
  def self.expires_in(time)
    (Time.now + time).to_i
  end

  def self.expired?(time)
    !!(time && time < Time.now.to_i)
  end
end
