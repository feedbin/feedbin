class ProfilesController < ApplicationController
  def index
    # @user = current_user
    @profiles = Profile.first.profile_name
    # @profiles = 'santi puto'
  end
end
