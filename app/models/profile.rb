class Profile < ApplicationRecord
    
    has_many :r_users_profiles
    has_many :users, through: :r_users_profiles

    has_many :r_profiles_tags
    has_many :tags, through: :r_profiles_tags
  
    def assing_profile_to_user(user_id)
        RUsersProfile.new( user_id: user_id, profile_id: self.id).save
    end

    def assign_tag_to_profile(user_id, tag_id)
        RProfilesTag.new( profile_id: user_id, tag_id: tag_id).save
    end
end
