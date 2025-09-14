class OnboardingController < ApplicationController

  def show
    render Onboarding::ShowView.new
  end
end
