class ErrorsController < ApplicationController
  skip_before_action :authorize

  def not_found
    render_404
  end
end
