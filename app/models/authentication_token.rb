class AuthenticationToken < ApplicationRecord
  belongs_to :user

  attr_accessor :length

  enum purpose: {cookies: 0, feeds: 1, newsletters: 2, pages: 2}

  scope :active, -> { where(active: true) }

  before_create :generate_token

  def generate_token
    begin
      self[:token] = SecureRandom.hex(length)
    end while AuthenticationToken.exists?(token: self[:token], purpose: purpose)
    self[:token]
  end
end
