class SuggestedCategory < ActiveRecord::Base
  has_many :suggested_feeds, dependent: :delete_all
end
