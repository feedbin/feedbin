class SuggestedFeed < ActiveRecord::Base
  belongs_to :suggested_category
  belongs_to :feed
end
