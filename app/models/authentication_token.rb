class AuthenticationToken < ApplicationRecord
  belongs_to :user

  attr_accessor :length, :skip_generate

  enum purpose: {cookies: 0, feeds: 1, newsletters: 2, pages: 3, app: 4, icloud: 5}

  scope :active, -> { where(active: true) }

  before_create :generate_token, unless: -> { skip_generate }

  def generate_token
    begin
      self[:token] = SecureRandom.hex(length)
    end while AuthenticationToken.exists?(token: self[:token], purpose: purpose)
    self[:token]
  end
end
