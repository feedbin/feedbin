class Profile < ApplicationRecord
    
    has_many :r_users_profiles
    has_many :users, through: :r_users_profiles

    has_many :r_profiles_tags
    has_many :tags, through: :r_profiles_tags
  
    # Desc: This method is used to assign a profile to users.
    #       First, try to find out if the user has the profile.
    #           -If the user has the profile, it will do nothing.
    #           -If the relationship between user and profile 
    #            is not found, then do insert
    #
    # input parameters: 
    #       @params[:user_id] [int]: id of User
    #
    def assign_profile_to_user(user_id)
        RUsersProfile.where(user_id: user_id, profile_id: self.id).empty? ? 
            RUsersProfile.create(user_id: user_id, profile_id: self.id) : "Profile already assigned to user"
    end

    # Desc: This method is used to assign a profile to users.
    #       First, try to find out if the user has the profile.
    #           -If the user has the profile, it will do nothing.
    #           -If the relationship between user and profile 
    #            is not found, then do insert
    #
    # input parameters: 
    #       @params[:tag_id] [int]: id of Tag
    #
    def assign_tag_to_profile(tag_id)
        RProfilesTag.where(profile_id: self.id, tag_id: tag_id).empty? ?
            RProfilesTag.create( profile_id: self.id, tag_id: tag_id) : "Tag already assigned to profile"
        end
    end
end
