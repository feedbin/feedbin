class SharingServicesController < ApplicationController

  def index
    @user = current_user
    native_serivces = @user.sharing_services.where(group: 'native')
    @native_serivces = {}
    native_serivces.each do |native_serivce|
      @native_serivces[native_serivce.service_id] = native_serivce
    end
    logger.info { @native_serivces.inspect }
    render layout: 'settings'
  end

  def oauth_request
    @user = current_user
    if params[:service] == 'pocket'
      oauth_request_pocket
    else
      redirect_to sharing_services_url, error: "Unknown service."
    end
  end

  def oauth_response
    @user = current_user
    if params[:service] == 'pocket'
      oauth_response_pocket
    else
      redirect_to sharing_services_url, error: "Unknown service."
    end
  end

  def auth_delete
    @user = current_user
    if %w{pocket}.include?(params[:service])
      service_info = SharingService.find_native_service!(params[:service])
      @user.sharing_services.unscoped.where(service_id: params[:service]).destroy_all
      redirect_to sharing_services_url, notice: "#{service_info[:label]} has been deactivated."
    else
      redirect_to sharing_services_url, notice: "Unknown service."
    end
  end

  def share
    @user = current_user
    entry = Entry.find(params[:id])
    url = ''
    if params[:service] == 'pocket'
      pocket = Pocket.new
      sharing_service = @user.sharing_services.unscoped.where(service_id: 'pocket').first
      response = pocket.add(sharing_service.access_token, entry.fully_qualified_url)
      if response.code == 401
        @user.sharing_services.unscoped.where(service_id: 'pocket').update_all(access_token: nil)
        url = sharing_services_path
      end
      render json: {service: sharing_service.label, status: response.code, url: url}.to_json
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
    pocket = Pocket.new;
    token = pocket.oauth_authorize(session[:pocket_oauth_token])
    if token.present?
      service_info = SharingService.find_native_service!('pocket')
      result = @user.sharing_services.unscoped.where(service_id: 'pocket').update_all(access_token: token)
      if result == 0
        @user.sharing_services.create(label: service_info[:label], group: "native", service_id: service_info[:service_id], access_token: token)
      end
      session.delete(:pocket_oauth_token)
      redirect_to sharing_services_url, notice: "Pocket has been activated!"
    else
      redirect_to sharing_services_url, error: "Authentication error"
    end
  end

  def oauth_request_pocket
    pocket = Pocket.new;
    token = pocket.request_token
    session[:pocket_oauth_token] = token
    redirect_to pocket.redirect_url(token)
  end

end
