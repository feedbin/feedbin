class ProfilesController < ApplicationController
    def index
        @user = current_user
        @profiles = @user.profiles
    end

    def get_tags_by_profile
        profile = Profile.find(params[:profile_id])
        tags = profile.tags
        render json: tags
    end
end
