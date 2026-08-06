class DevicesController < ApplicationController
  def create
    @user = current_user
    token = params[:device][:data][:endpoint]
    if token.nil?
      head :not_found and return
    end

    Device.register(@user, token, {
      token: token,
      device_type: :browser,
      model: request.env["HTTP_USER_AGENT"],
      data: device_params[:data]
    })

    head :ok
  end

  def device_params
    params.require(:device).permit(data: {})
  end
end
