class RecentlyReadEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry
  validates_uniqueness_of :user_id, scope: :entry_id
end
