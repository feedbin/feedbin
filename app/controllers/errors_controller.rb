class ErrorsController < ApplicationController
  skip_before_action :authorize

  def not_found
    respond_to do |format|
      format.any do
        render "errors/not_found.html.erb", layout: nil, status: :not_found
      end
    end
  end
end
