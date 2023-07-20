class ProfilesController < ApplicationController
    include ExampleConcern

    def index
        @user = current_user
        @my_profiles = @user.profiles

        @profiles = Profile.all
    end

    def subscribe
        puts Profile.find(params[:profile_id]).assing_profile_to_user(@user.id)

        redirect_to profiles_path
    end


end
