class ErrorsController < ApplicationController
  skip_before_action :authorize

  def not_found
    render_file_or("404", :not_found) {
      render plain: "Not found", status: :not_found
    }
  end
end
