class SharingServicesController < ApplicationController

  def index
    @user = current_user
    render layout: 'settings'
  end

  def sharing_services_update
    @user = current_user
    @user.free_ok = (@user.plan.stripe_id == 'free')
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


end
