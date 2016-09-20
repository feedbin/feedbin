class SuggestedCategory < ApplicationRecord
  has_many :suggested_feeds, dependent: :delete_all
end
