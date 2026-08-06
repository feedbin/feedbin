class ErrorsController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  def not_found
    render_404
  end
end
