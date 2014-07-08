require 'rails_helper'

describe UnreadEntriesController do
  describe "#update" do
    it "marks as read" do
      user = create(:user)
      subscription = create(:subscription, user: user)

      entry = create(:entry, feed: subscription.feed)

      sign_in user

      UnreadEntry.create_from_owners(subscription.user, entry)

      expect {
        post :update, id: entry.id, read: 'true', format: :js
      }.to change(UnreadEntry, :count).by(-1)
    end

    it "marks as unread" do
      user = create(:user)
      subscription = create(:subscription, user: user)

      entry = create(:entry, feed: subscription.feed)

      sign_in user

      expect {
        post :update, id: entry.id, read: 'false', format: :js
      }.to change(UnreadEntry, :count).by(1)
    end
  end
end
