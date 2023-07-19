class ProfilesController < ApplicationController
    def index
        @user = current_user
        @profiles = @user.profiles
    end

    def show
        @profile = Profile.find(params[:id])
    end

    # def show
    #     @user = current_user
    
    #     @profile = Profile.find(params[:id])
    #     @tag_ids = RProfileTags.where(profile_id: @profile, user_id: @user).pluck(:feed_id)
    
    #     feeds_response
    
    #     @collection_title = @tag.name
    
    #     respond_to do |format|
    #       format.js { render partial: "shared/entries" }
    #     end
    #   end
end
