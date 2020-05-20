class ErrorsController < ApplicationController
  skip_before_action :authorize

  def not_found
    respond_to do |format|
      format.any do
        render layout: nil, status: :not_found
      end
    end
  end
end
