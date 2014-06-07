require 'rails_helper'

describe Subscription do
  describe "#mark_as_read" do
    it "works" do
      subscription = create(:subscription)

      entry = create(:entry, feed: subscription.feed)

      expect {
        UnreadEntry.create_from_owners(subscription.user, entry)
      }.to change(UnreadEntry, :count).by(1)

      expect {
        subscription.mark_as_read
      }.to change(UnreadEntry, :count).by(-1)
    end
  end

  describe "#mark_as_unread" do
    it "works" do
      subscription = create(:subscription)

      entry = create(:entry, feed: subscription.feed)

      expect {
        subscription.mark_as_unread
      }.to change(UnreadEntry, :count).by(1)
    end
  end
end
