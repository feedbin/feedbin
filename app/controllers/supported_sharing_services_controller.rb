class SupportedSharingServicesController < ApplicationController

  def create
    @user = current_user
    supported_sharing_service = SupportedSharingService.find(params[:id])
    if SharingService.create_supported_service(@user, supported_sharing_service, supported_sharing_service_params)
      redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
    else
      redirect_to sharing_services_url, notice: "Unknown #{supported_sharing_service.label} error."
    end
  end

  def destroy
    @user = current_user
    supported_sharing_service = SupportedSharingService.find(params[:id])
    SharingService.unscoped.where(user: @user, service_id: params[:id]).destroy_all
    redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been deactivated."
  end

  def share
    @user = current_user
    url = ''
    entry = Entry.find(params[:id])
    sharing_service = SharingService.unscoped.where(user: @user, service_id: params[:service]).first!
    if sharing_service.access_token.present?
      if params[:service] == 'pocket'
        klass = Pocket.new(sharing_service.access_token)
      elsif params[:service] == 'readability'
        klass = Readability.new(sharing_service.access_token, sharing_service.access_secret)
      elsif params[:service] == 'instapaper'
        klass = Instapaper.new(sharing_service.access_token, sharing_service.access_secret)
      end
      response = klass.add(entry.fully_qualified_url)
      if response == 401
        SharingService.remove_access(@user, params[:service])
        url = sharing_services_path
      end
    else
      response = 401
      url = sharing_services_path
    end
    render json: {service: sharing_service.label, status: response, url: url}.to_json
  end

  def xauth_request
    @user = current_user
    supported_sharing_service = SupportedSharingService.find(params[:id])

    if supported_sharing_service.service_id == 'readability'
      klass = Readability.new
    elsif supported_sharing_service.service_id == 'instapaper'
      klass = Instapaper.new
    end

    begin
      response = klass.request_token(params[:username], params[:password])
      if response.token && response.secret
        SharingService.create_or_update_supported_service(@user, supported_sharing_service, access_token: response.token, access_secret: response.secret)
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      else
        redirect_to sharing_services_url, notice: "Unknown #{supported_sharing_service.label} error."
      end
    rescue OAuth::Unauthorized
      redirect_to sharing_services_url, notice: "Invalid username or password."
    rescue
      redirect_to sharing_services_url, notice: "Unknown #{supported_sharing_service.label} error."
    end
  end

  def oauth_request
    @user = current_user
    if params[:id] == 'pocket'
      oauth_request_pocket
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  def oauth_response
    @user = current_user
    if params[:id] == 'pocket'
      oauth_response_pocket
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  private

  def supported_sharing_service_params
    params.permit(:email_name, :email_address, :kindle_address)
  end

  def oauth_response_pocket
    pocket = Pocket.new
    supported_sharing_service = SupportedSharingService.find('pocket')
    response = pocket.oauth_authorize(session[:pocket_oauth_token])
    session.delete(:pocket_oauth_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      SharingService.create_or_update_supported_service(@user, supported_sharing_service, access_token: access_token)
      redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
    elsif response.code == 403
      redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{supported_sharing_service.label}."
    else
      Honeybadger.notify(
        error_class: "Pocket",
        error_message: "Pocket::oauth_authorize Failure",
        parameters: response
      )
      redirect_to sharing_services_url, alert: "Unknown #{supported_sharing_service.label} error."
    end
  end

  def oauth_request_pocket
    pocket = Pocket.new
    response = pocket.request_token
    if response.code == 200
      token = response.parsed_response['code']
      session[:pocket_oauth_token] = token
      redirect_to pocket.redirect_url(token)
    else
      Honeybadger.notify(
        error_class: "Pocket",
        error_message: "Pocket::request_token Failure",
        parameters: response
      )
      redirect_to sharing_services_url, notice: "Unknown Pocket error."
    end
  end

end
