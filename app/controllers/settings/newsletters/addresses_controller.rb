class Settings::Newsletters::AddressesController < ApplicationController
  layout "settings"

  before_action :set_address, only: [:update, :destroy, :activate]

  def show
    user = current_user
    address = user.newsletter_addresses.find(params[:id])
    render Settings::Newsletters::Addresses::ShowView.new(address: address)
  end

  def new
    render Settings::Newsletters::Addresses::NewView.new(user: current_user)
  end

  def update
    @address.update(address_params)
  end

  def destroy
    @address.update(active: false)
    redirect_to settings_newsletters_url, notice: "Address deactivated."
  end

  def activate
    @address.update(active: true)
    redirect_to settings_newsletters_url, notice: "Address activated."
  end

  def inactive
    render Settings::Newsletters::Addresses::InactiveView.new(addresses: current_user.inactive_newsletter_addresses)
  end

  def create
    user = current_user
    if params[:button_action] == "save"
      @address = if params[:authentication_token][:type] == "random"
        user.authentication_tokens.newsletters.create_with(address_params).create
      else
        token = Rails.application.message_verifier(:address_token).verify(params[:authentication_token][:verified_token])
        record = user.authentication_tokens.newsletters.create(token: token)
        record.update(address_params)
        record
      end
    else
      if params[:authentication_token][:type] == "random"
        @random = true
      elsif clean_token.present?
        @token = AuthenticationToken.newsletters.generate_custom_token(clean_token)
        @numbers = @token.split(".").last
        @message = Rails.application.message_verifier(:address_token).generate(@token)
      end
    end
  end

  private

  def clean_token
    params[:authentication_token][:token].present? && params[:authentication_token][:token].downcase.gsub(/[^a-z0-9\-\._]+/, "")
  end

  def address_params
    params.require(:authentication_token).permit(:description, :newsletter_tag)
  end

  def set_address
    @address = @user.authentication_tokens.newsletters.find(params[:id])
  end


end
