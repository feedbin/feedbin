class SupportedSharingServicesController < ApplicationController

  def create
    @user = current_user
    if params[:supported_sharing_service][:operation] == 'authorize'
      authorize_service(params[:supported_sharing_service][:service_id])
    else
      supported_sharing_service = @user.supported_sharing_services.new(supported_sharing_service_params)
      if supported_sharing_service.save
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      else
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      end
    end
  end

  def destroy
    @user = current_user
    supported_sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    label = supported_sharing_service.label
    supported_sharing_service.destroy
    redirect_to sharing_services_url, notice: "#{label} has been deactivated."
  end

  def update
    @user = current_user
    supported_sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    if params[:supported_sharing_service][:operation] == 'authorize'
      authorize_service(supported_sharing_service.service_id)
    else
      if supported_sharing_service.update(supported_sharing_service_params)
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      else
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      end
    end
  end

  def authorize_service(service_id)
    service_info = SupportedSharingService.info!(service_id)
    if service_info[:service_type] == 'oauth2_pocket'
      oauth2_pocket_request(service_id)
    elsif service_info[:service_type] == 'oauth'
      oauth_request(service_id)
    elsif service_info[:service_type] == 'xauth' || service_info[:service_type] == 'pinboard'
      xauth_request(service_id)
    end
  end

  def share
    @user = current_user
    sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    Librato.increment('supported_sharing_services.share', source: sharing_service.service_id)
    @response = sharing_service.share(params)
  end

  def xauth_request(service_id)
    @user = current_user
    service_info = SupportedSharingService.info!(service_id)
    klass = service_info[:klass].constantize.new

    begin
      response = klass.request_token(params[:username], params[:password])
      if response.token && response.secret
        supported_sharing_service = @user.supported_sharing_services.where(service_id: service_id).first_or_initialize
        supported_sharing_service.update(access_token: response.token, access_secret: response.secret)
        if supported_sharing_service.errors.any?
          redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
        else
          redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
        end
      else
        redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
      end
    rescue OAuth::Unauthorized
      redirect_to sharing_services_url, alert: "Invalid #{service_info[:label]} username or password."
    rescue
      redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
    end
  end

  def oauth2_pocket_response
    @user = current_user

    service_info = SupportedSharingService.info!(params[:id])
    klass = service_info[:klass].constantize.new

    response = klass.oauth2_pocket_authorize(session[:oauth2_pocket_token])
    session.delete(:oauth2_pocket_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      supported_sharing_service = @user.supported_sharing_services.where(service_id: params[:id]).first_or_initialize
      supported_sharing_service.update(access_token: access_token)
      if supported_sharing_service.errors.any?
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      else
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      end
    elsif response.code == 403
      redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{supported_sharing_service.label}."
    else
      Honeybadger.notify(
        error_class: "SupportedSharingServicesController#oauth2_pocket_response",
        error_message: "#{service_info[:label]} failure",
        parameters: response
      )
      redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
    end

  end

  def oauth_response
    @user = current_user
    service_info = SupportedSharingService.info!(params[:id])
    klass = service_info[:klass].constantize.new
    if params[:oauth_verifier].present?
      access_token = klass.request_access(session[:oauth_token], session[:oauth_secret], params[:oauth_verifier])
      session.delete(:oauth_token)
      session.delete(:oauth_secret)
      supported_sharing_service = @user.supported_sharing_services.where(service_id: params[:id]).first_or_initialize
      supported_sharing_service.update(access_token: access_token.token, access_secret: access_token.secret)
      if supported_sharing_service.errors.any?
        redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
      else
        supported_sharing_service.try(:after_activate)
        redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
      end
    else
      redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{service_info[:label]}."
    end
  rescue OAuth => e
    Honeybadger.notify(
      error_class: "SupportedSharingServicesController#oauth_response",
      error_message: "#{service_info[:label]} failure",
      parameters: e
    )
    redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
  end

  private

  def supported_sharing_service_params
    params.require(:supported_sharing_service).permit(:service_id, :email_name, :email_address, :kindle_address)
  end


  def oauth2_pocket_request(service_id)
    service_info = SupportedSharingService.info!(service_id)
    klass = service_info[:klass].constantize.new
    response = klass.request_token
    if response.code == 200
      token = response.parsed_response['code']
      session[:oauth2_pocket_token] = token
      redirect_to klass.redirect_url(token)
    else
      Honeybadger.notify(
        error_class: "SupportedSharingServicesController#oauth2_pocket_request",
        error_message: "#{service_info[:label]} failure",
        parameters: response
      )
      redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
    end
  end

  def oauth_request(service_id)
    service_info = SupportedSharingService.info!(service_id)
    klass = service_info[:klass].constantize.new
    response = klass.request_token
    if response.token && response.secret
      session[:oauth_token] = response.token
      session[:oauth_secret] = response.secret
      redirect_to response.authorize_url
    else
      redirect_to sharing_services_url, notice: "Unknown #{SupportedSharingService.info(service_id)[:label]} error."
    end
  rescue OAuth => e
    Honeybadger.notify(
      error_class: "SupportedSharingServicesController#oauth_request",
      error_message: "#{service_info[:label]} failure",
      parameters: e
    )
    redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
  end

end
