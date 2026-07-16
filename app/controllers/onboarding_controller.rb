class OnboardingController < ApplicationController

  def show
  end

  def update
    @user.setting_off!(:needs_onboarding)
  end
end
