require 'rails_helper'

describe User, type: :model do
  describe "#subscribe" do
    it "works" do
      user = create(:user)
      feed = create(:feed)

      expect {
        user.subscribe!(feed)
      }.to change(Subscription, :count).by(1)

      subscription = Subscription.last
      expect(subscription.user).to eq user
      expect(subscription.feed).to eq feed
    end
  end

  describe "#subscribed_to?" do
    it "works" do
      user = create(:user)
      feed = create(:feed)
      subscription = create(:subscription, feed: feed, user: user)

      expect(user.subscribed_to?(feed)).to eq true
    end
  end

  describe "#destroy" do
    it "creates DeletedUser record" do
      user = create(:user)
      expect {
        user.destroy
      }.to change(DeletedUser, :count).by(1)

      record = DeletedUser.last
      expect(record.email).to eq user.email
      expect(record.customer_id).to eq user.customer_id
    end
  end
end
