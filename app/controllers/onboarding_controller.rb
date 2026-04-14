class OnboardingController < ApplicationController

  def show
    # @class = "theme-dusk"
    render Onboarding::ShowView.new
  end

  def update
    @user.setting_off!(:needs_onboarding)
  end
end
