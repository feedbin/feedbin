class OnboardingController < ApplicationController

  def show
    # @class = "theme-dusk"
    render Onboarding::ShowView.new
  end
end
