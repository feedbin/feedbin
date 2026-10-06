class Admin::ApplicationController < ApplicationController
  private

  def authorize
    unless current_user.try(:admin?)
      render_404
    end
  end
end
