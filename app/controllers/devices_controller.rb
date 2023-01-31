class DevicesController < ApplicationController
  def create
    @user = current_user
    token = params[:device][:data][:endpoint]
    if token.nil?
      head :not_found and return
    end

    update = {
      token: token,
      model: request.env["HTTP_USER_AGENT"],
      data: device_params[:data]
    }

    device = @user.devices.browser.where_lower(token: token).take || @user.devices.browser.create(update)
    device.update(update)

    head :ok
  end

  def device_params
    params.require(:device).permit(data: {})
  end
end
