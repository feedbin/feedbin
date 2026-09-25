# A Twitter avatar by its URL, as a redirect the FILES_HOST CDN caches: to
# the stored copy forever, or to camo for a day when there is no copy, so a
# copy run that lands later still reaches readers. It answers the icon
# proxy's old path, so URLs the CDN cached as proxied bodies keep serving
# from the cache. Only the CDN reaches the
# origin; it adds the pull header. The response is public, so it sets no
# cookie: the CSRF cookie would write the session, and both would reach
# every viewer the CDN serves.
class TwitterAvatarsController < ApplicationController
  skip_before_action :authorize
  skip_after_action :set_csrf_cookie

  AUTH_HEADER = "X-Pull".freeze

  def show
    url = TwitterAvatar.decode(params[:url])

    unless ENV["FILES_AUTH_KEY"] == request.headers[AUTH_HEADER]
      head :not_found and return
    end

    unless TwitterAvatar.signature_valid?(params[:signature], url)
      head :not_found and return
    end

    unless url.start_with?("http")
      head :not_found and return
    end

    if (stored = TwitterAvatar.resolve(url))
      expires_in 100.years, public: true
      redirect_to stored, allow_other_host: true
    else
      expires_in 1.day, public: true
      redirect_to Camo.url(url), allow_other_host: true
    end
  end
end
