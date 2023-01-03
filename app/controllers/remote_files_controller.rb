class RemoteFilesController < ApplicationController

  AUTH_KEY        = ENV["FILES_AUTH_KEY"]
  AUTH_HEADER     = "X-Pull".freeze
  URL_HEADER      = "X-File-URL".freeze
  HOST_HEADER     = "X-File-Host".freeze
  SIZE_HEADER     = "X-Image-Size".freeze
  PROXY_PATH      = "/remote_image".freeze
  SENDFILE_HEADER = Rails.application.config.action_dispatch.x_sendfile_header

  def icon
    unless @url.start_with?("http")
      head :not_found and return
    end

    unless RemoteFile::BUCKET
      redirect_to @url and return
    end

    size = %w(32 64 128 200 400).include?(params[:size]) ? params[:size] : "400"
    proxy_url = if icon = RemoteFile.find_by(fingerprint: RemoteFile.fingerprint(@url))
      icon.storage_url
    else
      ImageCrawler::CacheRemoteFile.schedule(@url)
      camo_url
    end


    proxy_response(proxy_url:, size:)
  end

  def favicon
    icon = RemoteFile.find_by(fingerprint: RemoteFile.fingerprint(@url))

    if icon.nil?
      head :not_found and return
    end

    size      = %w(32 64 128 180).include?(params[:size]) ? params[:size] : "180"
    proxy_url = icon.storage_url

    proxy_response(proxy_url:, size:)
  end

  def proxy_response(proxy_url:, size:)
    parsed = URI(proxy_url)
    response.headers[SENDFILE_HEADER] = PROXY_PATH
    response.headers[SIZE_HEADER]     = size
    response.headers[HOST_HEADER]     = parsed.host
    response.headers[URL_HEADER]      = proxy_url

    http_cache_forever(public: true) do
      head :ok
    end
  end

  private

  def authorize
    @url = RemoteFile.decode(params[:url])

    unless AUTH_KEY == request.headers[AUTH_HEADER]
      head :not_found and return
    end

    unless RemoteFile.signature_valid?(params[:signature], @url)
      head :not_found and return
    end
  end

  def camo_url
    "#{ENV["CAMO_HOST"]}/#{params[:signature]}/#{params[:url]}"
  end
end
