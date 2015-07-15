class ErrorsController < ApplicationController

  skip_before_action :authorize

  def not_found
    render layout: 'sub_page', status: :not_found
  end

  def service_unavailable
    render layout: 'sub_page'
  end

end
