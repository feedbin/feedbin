class ErrorsController < ApplicationController
  skip_before_action :authorize

  def not_found
    render layout: nil
  end
end
