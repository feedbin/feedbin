require 'rails_helper'

describe SessionsController do
  describe "#create" do
    let(:password) { "foobarisnoteasy" }

    it "works" do
      user = create(:user, password: password)
      post :create, email: user.email, password: password

      expect(response.status).to eq 302
      expect(response).to redirect_to root_url
    end
  end

  describe "#destroy" do
    it "works" do
      user = create(:user)
      sign_in user

      post :destroy

      expect(session[:auth_token]).to be_nil
      expect(response).to redirect_to root_path
    end
  end
end
