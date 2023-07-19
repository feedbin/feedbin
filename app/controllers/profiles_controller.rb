class ProfilesController < ApplicationController
    def index
        @user = current_user
        @profiles = @user.profiles
    end

    def show
        @profile = Profile.find(params[:id])
    end
end
