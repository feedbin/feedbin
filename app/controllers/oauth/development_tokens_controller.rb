# Mints a v3 access token for any local user, so a native client can sign in
# during development without the browser flow. The route only exists in
# development and test; the check here is a second lock.
class Oauth::DevelopmentTokensController < ActionController::API
  def create
    return head :not_found unless Rails.env.local?

    user = User.find_by(id: params[:user_id])
    return head :not_found unless user

    user.setting_on!(:api_v3)
    application = Api::V3::DevelopmentApplication.ensure!(owner: user)
    token = application.access_tokens.create!(
      resource_owner_id: user.id,
      device_name: "Development",
      scopes: Api::V3::Scopes.for(application)
    )

    render json: {
      access_token: token.plaintext_token,
      token_type: "Bearer",
      scope: token.scopes.to_s,
      created_at: token.created_at.to_i
    }
  end
end
