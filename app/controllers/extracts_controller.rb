class ExtractsController < ApplicationController

  def entry
    @user = current_user
    @entry = Entry.find params[:id]

    @extract = params[:extract] == "true"

    begin
      if @extract
        url = @entry.fully_qualified_url
        @content_info = MercuryParser.parse(url)
        @content = @content_info.content
      else
        @content = @entry.content
      end
    rescue => e
      @content = check_for_image(@entry, url)
    end

    begin
      @content = ContentFormatter.format!(@content, @entry)
    rescue
      @content = nil
    end
  end

  def modal
    @user = current_user
    @url = params[:url]
    @content_info = MercuryParser.parse(params[:url])

    begin
      @content = ContentFormatter.format!(@content_info.content, nil, true, params[:url])
    rescue
      @content = nil
    end
  end

  def cache
    ViewLinkCache.perform_async(params[:url], Expires.expires_in(1.minute))
    head :ok
  end

end
