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
    if service_id == 'pocket'
      oauth_request_pocket
    elsif %w{instapaper readability}.include?(service_id)
      xauth_request(service_id)
    else
      redirect_to sharing_services_url, alert: "Unknown service."
    end
  end

  def share
    @user = current_user
    sharing_service = @user.supported_sharing_services.where(id: params[:id]).first!
    status = sharing_service.share(params[:entry_id])
    response = {service: sharing_service.label, status: status}
    if status == 401
      response[:url] = sharing_services_path
    end
    render json: response.to_json
  end

  def xauth_request(service_id)
    @user = current_user
    service_info = SupportedSharingService.info(service_id)

    if service_id == 'readability'
      klass = Readability.new
    elsif service_id == 'instapaper'
      klass = Instapaper.new
    end

    begin
      response = klass.request_token(params[:username], params[:password])
      if response.token && response.secret
        supported_sharing_service = @user.supported_sharing_services.first_or_initialize(service_id: service_id)
        supported_sharing_service.update(access_token: response.token, access_secret: response.secret)
        if supported_sharing_service.errors.any?
          redirect_to sharing_services_url, alert: supported_sharing_service.errors.full_messages.join('. ')
        else
          redirect_to sharing_services_url, notice: "#{supported_sharing_service.label} has been activated!"
        end
      else
        redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
      end
    rescue OAuth::Unauthorized
      redirect_to sharing_services_url, notice: "Invalid username or password."
    rescue
      redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
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
    params.require(:supported_sharing_service).permit(:service_id, :email_name, :email_address, :kindle_address)
  end

  def oauth_response_pocket
    pocket = Pocket.new
    response = pocket.oauth_authorize(session[:pocket_oauth_token])
    session.delete(:pocket_oauth_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      supported_sharing_service = @user.supported_sharing_services.first_or_initialize(service_id: 'pocket')
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
        error_class: "Pocket",
        error_message: "Pocket::oauth_authorize Failure",
        parameters: response
      )
      redirect_to sharing_services_url, alert: "Unknown #{SupportedSharingService.info('pocket')[:label]} error."
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
      redirect_to sharing_services_url, notice: "Unknown #{SupportedSharingService.info('pocket')[:label]} error."
    end
  end

end
