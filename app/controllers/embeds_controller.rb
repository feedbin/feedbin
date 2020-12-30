class EmbedsController < ApplicationController
  def twitter
    @url = params[:url]
    @dom_id = params[:dom_id]
    @tweet = IframeEmbed::Twitter.new(@url)
  end

  def instagram
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = IframeEmbed::Instagram.new(@url)
  end

  def iframe
    @url = params[:url]
    @dom_id = params[:dom_id]
    @embed = IframeEmbed.fetch(@url)
  end
end
