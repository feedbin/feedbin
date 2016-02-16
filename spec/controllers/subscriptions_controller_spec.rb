require 'rails_helper'

describe SubscriptionsController do
  describe "#index" do
    it "works" do
      user = create(:user)
      feed = create(:feed)
      subscription = create(:subscription, user: user, feed: feed)

      sign_in user

      get :index, format: :xml

      expect(response.status).to eq 200

      expect(assigns(:feeds)).to eq [feed]
    end
  end

  describe "#destroy" do
    it "works" do
      user = create(:user)
      feed = create(:feed)
      subscription = create(:subscription, user: user, feed: feed)

      sign_in user

      expect {
        post :destroy, format: :js, id: subscription.id
      }.to change(Subscription, :count).by(-1)

      expect(response.status).to eq 200
    end
  end

  # describe "#create" do
  #   it "works" do
  #     user = create(:user)
  #     sign_in user
  #
  #     fake_feed_fetcher = double(feed: create(:feed))
  #     allow_any_instance_of(FeedFetcher).to receive(:create_feed!).and_return(fake_feed_fetcher)
  #
  #     expect {
  #       post :create, subscription: {
  #         site_url: 'http://tema.livejournal.com/',
  #         feeds: {
  #           feed_url: 'http://tema.livejournal.com/feed.rss'
  #         }
  #       }, format: :js
  #     }.to change(Subscription, :count).by(1)
  #
  #     expect(response.status).to eq 200
  #
  #     results = assigns(:results)
  #     expect(results[:success].size).to eq 1
  #   end
  # end

  describe "#update_multiple" do
    context "unsubscribe" do
      it "works" do
        user = create(:user)
        sign_in user

        subscription = create(:subscription, user: user)
        post :update_multiple, operation: 'unsubscribe', subscription_ids: [subscription.id]

        expect(response.status).to eq 302
        expect(response).to redirect_to(settings_feeds_url)
      end
    end
  end

end
