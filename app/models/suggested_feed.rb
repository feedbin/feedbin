class SuggestedFeed < ApplicationRecord
  belongs_to :suggested_category
  belongs_to :feed
end
