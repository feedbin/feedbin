class ExtractsController < ApplicationController
  def entry
    @user = current_user
    @entry = authorized_entry or return

    @extract = params[:extract] == "true"
    begin
      if @extract
        url = @entry.fully_qualified_url
        @content_info = MercuryParser.parse(url)
        @content = @content_info.content
      else
        @content = @entry.content
      end
    rescue => exception
      Rails.logger.error exception.message
      Rails.logger.error exception.backtrace.join("\n")
      @content = nil
    end

    begin
      @content = ContentFormatter.format!(@content, nil, true, url)
    rescue
      @content = nil
    end

    # JS for tabs from before the entry toolbar was rendered once; the toolbar
    # controller asks for HTML and does the DOM work itself.
    respond_to do |format|
      format.js
      format.html { render partial: "extracts/entry", locals: {content: @content, content_info: @content_info, entry: @entry, user: @user} }
    end
  end

  def modal
    @user = current_user
    @url = params[:url]

    begin
      @content_info = MercuryParser.parse(params[:url])
      @content = ContentFormatter.format!(@content_info.content, nil, true, params[:url])
    rescue => exception
      Rails.logger.info { exception }
      @content = nil
    end
  end

  def cache
    ViewLinkCache.perform_async(params[:url], Expires.expires_in(1.minute))
    head :ok
  end
end
