class Profile < ApplicationRecord
    
    has_many :r_users_profiles
    has_many :users, through: :r_users_profiles

    has_many :r_profiles_tags
    has_many :tags, through: :r_profiles_tags

    def assing_profile_to_user(user_id, profile_id)
        RUsersProfile( user_id: user_id, profile_id: profile_id).save
    end

    def assign_profile_to_tag(user_id, tag_id)
        RProfilesTag( profile_id: user_id, tag_id: tag_id).save
    end
end
