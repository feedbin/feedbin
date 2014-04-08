class SharingServicesController < ApplicationController

  def index
    @user = current_user
    active_services = @user.sharing_services.where(sharing_type: 'supported')
    @active_services = {}
    active_services.each do |active_service|
      @active_services[active_service.service_id] = active_service
    end
    render layout: 'settings'
  end

  def xauth_request
    @user = current_user
    if params[:service] == 'readability'
      xauth_request_readability
    else
      redirect_to sharing_services_url, alert: "Unknown service."
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

  def auth_delete
    @user = current_user
    if %w{pocket readability}.include?(params[:service])
      service_info = SharingService.find_supported_service!(params[:service])
      SharingService.unscoped.where(user: @user, service_id: params[:service]).destroy_all
      redirect_to sharing_services_url, notice: "#{service_info[:label]} has been deactivated."
    else
      redirect_to sharing_services_url, notice: "Unknown service."
    end
  end

  def share
    @user = current_user
    entry = Entry.find(params[:id])
    if params[:service] == 'pocket'
      share_pocket(entry)
    elsif params[:service] == 'readability'
      share_readability(entry)
    else
      render nothing: true
    end
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

  def sharing_services_params
    if params[:user][:sharing_services_attributes]
      owned_services = @user.sharing_services.pluck(:id)
      requested_services = params[:user][:sharing_services_attributes].collect { |index, sharing_services| {index: index, id: sharing_services['id']} }
      requested_services.each do |service|
        next if service[:index] =~ /_insert$/
        unless owned_services.include?(service[:id].to_i)
          params[:user][:sharing_services_attributes].delete(service[:index])
        end
      end
      params[:user][:sharing_services_attributes].map {|index, sharing_services| params[:user][:sharing_services_attributes][index] = sharing_services.slice(:id, :label, :url, :_destroy) }
    end
    params.require(:user).permit!
  end

  def oauth_response_pocket
    pocket = Pocket.new
    service_info = SharingService.find_supported_service!('pocket')
    response = pocket.oauth_authorize(session[:pocket_oauth_token])
    session.delete(:pocket_oauth_token)
    if response.code == 200
      access_token = response.parsed_response['access_token']
      result = SharingService.unscoped.where(user: @user, service_id: 'pocket').update_all(access_token: access_token)
      if result == 0
        @user.sharing_services.create(label: service_info[:label], sharing_type: "supported", service_id: service_info[:service_id], access_token: access_token)
      end
      redirect_to sharing_services_url, notice: "#{service_info[:label]} has been activated!"
    elsif response.code == 403
      redirect_to sharing_services_url, alert: "Feedbin needs your permission to activate #{service_info[:label]}."
    else
      Honeybadger.notify(
        error_class: "Pocket",
        error_message: "Pocket::oauth_authorize Failure",
        parameters: response
      )
      redirect_to sharing_services_url, alert: "Unknown #{service_info[:label]} error."
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

  def xauth_request_readability
    service_info = SharingService.find_supported_service!(params[:service])
    readability = Readability.new
    begin
      response = readability.request_token(params[:username], params[:password])
      if response.token && response.secret
        result = SharingService.unscoped.where(user: @user, service_id: 'readability').update_all(access_token: response.token, access_secret: response.secret)
        if result == 0
          @user.sharing_services.create(label: service_info[:label], sharing_type: "supported", service_id: service_info[:service_id], access_token: response.token, access_secret: response.secret)
        end
        redirect_to sharing_services_url, notice: "#{service_info[:label]} has been activated!"
      else
        redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
      end
    rescue OAuth::Unauthorized
      redirect_to sharing_services_url, notice: "Invalid username or password."
    rescue
      redirect_to sharing_services_url, notice: "Unknown #{service_info[:label]} error."
    end
  end

  def share_pocket(entry)
    url = ''
    pocket = Pocket.new
    sharing_service = SharingService.unscoped.where(user: @user, service_id: 'pocket').first
    response = pocket.add(sharing_service.access_token, entry.fully_qualified_url)
    if response.code == 401
      SharingService.remove_access(@user, sharing_service[:service_id])
      url = sharing_services_path
    end
    render json: {service: sharing_service.label, status: response.code, url: url}.to_json
  end

  def share_readability(entry)
    url = ''
    sharing_service = SharingService.unscoped.where(user: @user, service_id: 'readability').first
    readability = Readability.new(sharing_service.access_token, sharing_service.access_secret)
    response = readability.add(entry.fully_qualified_url)
    status = response.code.to_i
    if [202, 409].include?(status)
      status = 200
    elsif 401 == status
      SharingService.remove_access(@user, sharing_service[:service_id])
      url = sharing_services_path
    end
    render json: {service: sharing_service.label, status: status, url: url}.to_json
  end

end
