class SupportedSharingServicesController < ApplicationController

  def delete
    @user = current_user
    supported_sharing_service = SupportedSharingService.find(params[:service])
    SharingService.unscoped.where(user: @user, service_id: params[:service]).destroy_all
    redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been deactivated."
  end

  def xauth_request
    @user = current_user
    supported_sharing_service = SupportedSharingService.find(params[:service])

    if supported_sharing_service.service_id == 'readability'
      klass = Readability.new
    elsif supported_sharing_service.service_id == 'instapaper'
      klass = Instapaper.new
    end

    begin
      response = klass.request_token(params[:username], params[:password])
      if response.token && response.secret
        result = SharingService.unscoped.where(user: @user, service_id: supported_sharing_service.service_id).update_all(access_token: response.token, access_secret: response.secret)
        if result == 0
          @user.sharing_services.create(label: supported_sharing_service.label, sharing_type: "supported", service_id: supported_sharing_service.service_id, access_token: response.token, access_secret: response.secret)
        end
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
    if params[:service] == 'pocket'
      oauth_request_pocket
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  def oauth_response
    @user = current_user
    if params[:service] == 'pocket'
      oauth_response_pocket
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
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

  def sharing_services_update
    @user = current_user
    if @user.update_attributes(sharing_services_params)
      redirect_to sharing_services_url, notice: "Sharing services updated."
    else
      @messages = ['Error saving services.']
      flash[:error] = render_to_string partial: "shared/messages"
      redirect_to sharing_services_url
    end
  end

  private

  def oauth_response_pocket
    pocket = Pocket.new
    supported_sharing_service = SupportedSharingService.find('pocket')
    response = pocket.oauth_authorize(session[:pocket_oauth_token])
    session.delete(:pocket_oauth_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      result = SharingService.unscoped.where(user: @user, service_id: 'pocket').update_all(access_token: access_token)
      if result == 0
        @user.sharing_services.create(label: supported_sharing_service.label, sharing_type: "supported", service_id: supported_sharing_service.service_id, access_token: access_token)
      end
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
