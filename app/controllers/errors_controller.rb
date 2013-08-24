class ErrorsController < ApplicationController
  
  skip_before_action :authorize
  
  def not_found; end
  def service_unavailable; end
  
end
