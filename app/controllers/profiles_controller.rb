class ProfilesController < ApplicationController
    def index
        @user = current_user
        @profiles = @user.profiles
    end
end
