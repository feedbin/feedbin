class Profile < ApplicationRecord
    
    has_many :r_users_profiles
    has_many :users, through: :r_users_profiles

    has_many :r_profiles_tags
    has_many :tags, through: :r_profiles_tags
end
