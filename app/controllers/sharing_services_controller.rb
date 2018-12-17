class SharingServicesController < ApplicationController
  layout "settings"

  before_action :set_sharing_service, only: [:update, :destroy]

  def index
    @user = current_user

    @active_sharing_services = (@user.sharing_services + @user.supported_sharing_services)
    @active_sharing_services = @active_sharing_services.reject { |sharing_service| sharing_service.active? == false }.sort_by { |sharing_service| sharing_service.label }

    @active_service_ids = @active_sharing_services.collect { |service| service.try(:service_id) }.compact
    @available_sharing_services = SupportedSharingService::SERVICES.reject { |supported_service| supported_service[:active] == false }.sort_by { |supported_service| supported_service[:service_id] }
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

  def update
    if @sharing_service.update(sharing_service_params)
      redirect_to sharing_services_url, notice: "Sharing service was successfully updated."
    else
      redirect_to sharing_services_url, alert: "Update failed."
    end
  end

  def destroy
    @sharing_service.destroy
    redirect_to sharing_services_url, notice: "Sharing service was successfully deleted."
  end

  private

  def sharing_service_params
    params.require(:sharing_service).permit(:label, :url)
  end

  def set_sharing_service
    @sharing_service = @user.sharing_services.find(params[:id])
  end
end
