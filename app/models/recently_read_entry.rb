class RecentlyReadEntry < ApplicationRecord
  belongs_to :user
  belongs_to :entry
  validates_uniqueness_of :user_id, scope: :entry_id

  # Look up / insert by the columns the unique index covers so that a row
  # which is already there is returned rather than raising RecordInvalid,
  # and a concurrent request which wins the race is recovered via find_by
  # rather than raising RecordNotUnique.
  def self.create_from_owners(user, entry_id)
    create_or_find_by(user_id: user.id, entry_id: entry_id)
  end
end
