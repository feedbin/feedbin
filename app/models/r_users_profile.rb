class RUsersProfile < ApplicationRecord
    belongs_to :profile
    belongs_to :user

    validates :profile_id, uniqueness: { scope: :user_id }
end
