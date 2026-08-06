class PagesController < ApplicationController
  skip_before_action :authorize, only: [:options]

  after_action :cors_headers, only: [:create, :options]

  # The GET fallback that used to live here was removed with its route: a
  # request that saves a page is a state change and does not belong on GET.
  def create
    return head :bad_request if params[:url].blank?
    SavePage.perform_async(current_user.id, params[:url], params[:title])
    respond_to do |format|
      # The share target and the bookmarklet fallback both arrive as full-page
      # form navigations, so leave the user somewhere rather than on a blank
      # response.
      format.html { redirect_to root_url, notice: "Page saved!" }
      format.any { head :ok }
    end
  end

  def options
    head :ok
  end

  private

  # The bookmarklet and the extension post cross-origin, so they carry their own
  # credential rather than a forgery token. A request that authenticated on the
  # session cookie alone gets the normal check.
  def verify_authenticity_token
    super if params[:page_token].blank? && request.authorization.blank? && !browser_initiated?
  end

  # A Web Share Target launch is a browser-initiated top-level POST: like the
  # address bar it has no initiating origin, so the browser marks it
  # Sec-Fetch-Site: none and it cannot carry a forgery token. A cross-site form
  # post arrives marked cross-site and takes the forgery check as before, and
  # every browser that implements share targets sends the header.
  def browser_initiated?
    request.headers["Sec-Fetch-Site"] == "none"
  end

  def authorize
    @current_user ||= begin
      if signed_in?
        current_user
      elsif params[:page_token]
        User.find_by_page_token!(params[:page_token])
      else
        authenticate_or_request_with_http_basic("Feedbin") do |username, password|
          User.find_by_email(username).try(:authenticate, password)
        end
      end
    end
  end

  def cors_headers
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    headers["Access-Control-Allow-Headers"] = "Origin, Content-Type, Accept"
    headers["Access-Control-Max-Age"] = 1.hour.to_i.to_s
  end
end
