class AuthenticationToken < ApplicationRecord
  belongs_to :user

  attr_accessor :length, :skip_generate

  enum purpose: {cookies: 0, feeds: 1, newsletters: 2, pages: 3, app: 4, icloud: 5}

  store_accessor :data, :description, :newsletter_tag

  scope :active, -> { where(active: true) }

  before_create :generate_token, unless: -> { skip_generate }

  has_many :newsletter_senders, foreign_key: :token, primary_key: :token

  def generate_token
    begin
      self[:token] = token_strategy
    end while AuthenticationToken.exists?(token: self[:token], purpose: purpose)
    self[:token]
  end

  def token_strategy
    if newsletters?
      token_alpha
    else
      token_random
    end
  end

  def token_alpha
    Array.new(5) { ("a".."z").to_a.sample }.join
  end

  def token_random
    SecureRandom.hex(length)
  end

  def self.token_custom(prefix)
    token = nil
    count = AuthenticationToken.newsletters.where("token LIKE :query", query: "#{prefix}.%").count
    length = count > 900 ? 4 : 3
    1_000.times do |count|
      numbers = Array.new(length) { (0..9).to_a.sample }.join
      token = "#{prefix}.#{numbers}"
      break unless AuthenticationToken.exists?(token: token, purpose: :newsletters)
    end
    token
  end

  def title
    "#{token}@#{ENV["NEWSLETTER_ADDRESS_HOST"]}"
  end
end
