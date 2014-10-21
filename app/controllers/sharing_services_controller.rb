class SharingServicesController < ApplicationController

  layout 'settings'

  def index
    @user = current_user
    @active_sharing_services = @user.supported_sharing_services.order(:service_id)
    @active_service_ids = @active_sharing_services.collect {|service| service.service_id}
    @available_sharing_services = SupportedSharingService::SERVICES.sort_by {|supported_service| supported_service[:service_id]}
    @sharing_service = @user.sharing_services.new
  end

  def create
    @sharing_service = @user.sharing_services.new(sharing_service_params)
    if @sharing_service.save
      redirect_to sharing_services_url, notice: "Sharing service was successfully created."
    else
      redirect_to sharing_services_url, alert: "Save failed."
    end
  end

  private

  def sharing_service_params
    params.require(:sharing_service).permit(:label, :url)
  end

end
