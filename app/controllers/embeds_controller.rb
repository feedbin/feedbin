class EmbedsController < ApplicationController

  def twitter
    @tweet = TwitterEmbed.new(params[:url])
  end

  def instagram
  end


end
