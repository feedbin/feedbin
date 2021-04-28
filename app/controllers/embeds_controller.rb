class EmbedsController < ApplicationController
  def twitter
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed::Twitter.new(@url)
    render "embed", locals: {source: "twitter"}, formats: :js
  end

  def instagram
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed::Instagram.new(@url)
    render "embed", locals: {source: "instagram"}, formats: :js
  end

  def iframe
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed.fetch(@url)
    render "embed", locals: {source: "iframe"}, formats: :js
  end
end
