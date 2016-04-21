require 'rails_helper'

describe PasswordResetsController do
  describe "create" do
    it "works" do
      user = create(:user)
      sign_in user

      post :create, email: user.email

      user.reload
      expect(user.password_reset_sent_at).to be_present
      expect(user.password_reset_token).to be_present

      expect(response).to redirect_to login_path
    end
  end

  describe "#update" do
    it "works" do
      user = create(:user)

      token = user.generate_token(:password_reset_token, nil, true)
      user.password_reset_sent_at = Time.now
      user.save!

      post :update, id: token, user: { password: '12345678' }

      user.reload

      expect(user.password_reset_token).to be_nil
      expect(flash[:notice]).to eq "Password has been reset."

      expect(response).to redirect_to login_path
    end
  end
end
