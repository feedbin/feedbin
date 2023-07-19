class ProfilesController < ApplicationController
    def index
        @user = current_user
        @profiles = @user.profiles
    end

    def link_user_profile_tag(user_id, profile_id, tag_id)
        
        Profile.assing_profile_to_user(user_id, profile_id)
        Profile.assign_tag_to_profile(user_id, tag_id)
        
        # View tag
        Feed.assign_new_feeds(tag_id, user_id)
        Entry.mark_unread_entries_from_tag(tag_id, user_id)
    end
end
