# The version of one of a user's lists. A Postgres trigger bumps it on every
# insert or delete in the table behind the list (see the migration), so the
# v3 API can give the list an ETag without reading it.
class SyncVersion < ApplicationRecord
  belongs_to :user

  LISTS = %w[unread starred subscriptions].freeze

  def self.for(user)
    LISTS.index_with(0).merge(where(user_id: user.id, list: LISTS).pluck(:list, :version).to_h)
  end
end
