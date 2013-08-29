class Tag < ActiveRecord::Base
  attr_accessor :unread_count, :user_feeds

  has_many :taggings
  has_many :feeds, through: :taggings
end
