class ErrorsController < ApplicationController

  skip_before_action :authorize

  def not_found
    render layout: 'sub_page'
  end

  def service_unavailable
    render layout: 'sub_page'
  end

end
