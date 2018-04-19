class EmbedsController < ApplicationController

  def twitter
    @url = params[:url]
    @dom_id = params[:dom_id]
    @tweet = TwitterEmbed.new(@url)
  end

  def instagram
    @url = params[:url]
    @dom_id = params[:dom_id]
    @media = InstagramEmbed.new(@url)
  end


end
