class IconsController < ApplicationController
  skip_before_action :authorize, only: [:profile]
  skip_after_action :set_csrf_cookie, only: [:profile]

  def profile
    request.session_options[:skip] = true
    response.headers[Rails.application.config.action_dispatch.x_sendfile_header] = "/remote/"
    http_cache_forever(public: true) do
      head :ok
    end
  end
end
