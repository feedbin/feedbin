module ExampleConcern
    extend ActiveSupport::Concern
  
    # USER <- PROFILE
    # ALL_TAGS <- PROFILE [CARS, SPORTS, ...]


    def subsribe_profile(user_id, profile_id)
        Profile.assing_profile_to_user(user_id, profile_id)

        
    end

    def link_user_profile_tag(user_id, profile_id, tag_id)
        Profile.assign_tag_to_profile(user_id, tag_id)
        
        # View tag
        Feed.assign_new_feeds(tag_id, user_id)
        Entry.mark_unread_entries_from_tag(tag_id, user_id)
        return "done"
    end


  end
  