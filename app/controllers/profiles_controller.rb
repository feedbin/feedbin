class ProfilesController < ApplicationController
    include ExampleConcern

    def index
        @user = current_user
        @my_profiles = @user.profiles

        @profiles = Profile.all
    end

    def subscribe(profile_id)
        @test = profile_id
    end
end
