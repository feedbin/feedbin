class ProfilesController < ApplicationController
    include ExampleConcern

    def index
        @user = current_user
        @my_profiles = @user.profiles

        @profiles = Profile.all
    end

    def subscribe
        Profile.find(params[:profile_id]).assing_profile_to_user(@user.id)
        redirect_to root_path
    end
end
