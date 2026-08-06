class EmbedsController < ApplicationController
  def twitter
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed::Twitter.download(@url)
    render "embed", locals: {source: "twitter"}, formats: :js
  # TypeError as well as ParserError: UrlCache declines to cache a failed
  # response and hands back a nil body, which JSON.parse rejects as a type.
  rescue JSON::ParserError, TypeError
    head :ok
  end

  def instagram
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed::Instagram.download(@url)
    render "embed", locals: {source: "instagram"}, formats: :js
  rescue JSON::ParserError, TypeError
    head :ok
  end

  def iframe
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed.fetch(@url)
    render "embed", locals: {source: "iframe"}, formats: :js
  rescue
    @host = URI.parse(@url).host
    render "error", formats: :js
  end
end
