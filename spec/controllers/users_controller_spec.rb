require 'rails_helper'

describe UsersController do
  describe "#new" do
    context "with coupon code" do
      let(:coupon) { create(:coupon, coupon_code: 'foobar') }

      it "user.coupon is set" do
        get :new, coupon: coupon.coupon_code

        expect(assigns(:user).coupon_code).to eq coupon.coupon_code
      end

      it "user has free plan" do
        get :new, coupon: coupon.coupon_code

        expect(assigns(:user).plan).to eq Plan.find_by(stripe_id: 'free')
      end
    end
  end

  describe "#create" do
    let(:user_params) {
      {
        email: Faker::Internet.email,
        password: 'simplesampler',
        password_confirmation: 'simplesampler'
      }
    }

    it "creates new record" do
      expect {
        post :create, user: user_params
      }.to change(User, :count).by(1)

      user = User.last
      expect(user.email).to eq user_params[:email]
      expect(user.auth_token).to be_present

      expect(response).to redirect_to root_url
    end

    context "with coupon code" do
      let(:coupon) { create(:coupon, coupon_code: 'foobar') }

      it "user has free plan" do
        expect {
          post :create, user: user_params.merge(coupon_code: coupon.coupon_code)
        }.to change(User, :count).by(1)

        user = User.last
        expect(user.plan).to eq Plan.find_by(stripe_id: 'free')
        expect(user.free_ok).to eq true
      end
    end
  end

  describe "#update" do
    let(:new_email) { 'foo@bar.com' }
    it "updates the record" do
      user = create(:user)
      sign_in user

      post :update, id: user.id, user: { email: new_email }

      user.reload
      expect(user.email).to eq new_email

      expect(response).to redirect_to settings_account_path
    end
  end

  describe "#destroy" do
    context "under current user" do
      it "can be deleted" do
        user = create(:user)

        sign_in user

        expect {
          delete :destroy, id: user.id
        }.to change(DeletedUser, :count).by(1)

        expect(response.status).to eq 302

        expect {
          user.reload
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
