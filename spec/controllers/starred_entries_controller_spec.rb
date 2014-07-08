require 'rails_helper'

describe StarredEntriesController do
  describe "#index" do
    context "user has enabled stars" do
      it "works" do
        user = create(:user, starred_feed_enabled: 1)
        feed = create(:feed)

        entries = create_list(:entry, 2, feed: feed)

        create(:starred_entry, entry: entries[0], feed: feed, user: user)
        create(:starred_entry, entry: entries[1], feed: feed, user: user)

        sign_in user

        get :index, starred_token: user.starred_token, format: :xml

        expect(assigns(:entries).size).to eq 2
        expect(assigns(:starred_entries).size).to eq 2
      end
    end
  end

  describe "#export" do
    it "works" do
      user = create(:user, starred_feed_enabled: 1)
      sign_in user

      expect(StarredEntriesExport).to receive(:perform_async).once.with(user.id)

      get :export

      expect(response).to redirect_to settings_import_export_path
    end
  end

  describe "#update" do
    context "with starred=true" do
      context "not starred yet" do
        it "works" do
          user = create(:user, starred_feed_enabled: 1)
          sign_in user

          entry = create(:entry)

          expect {
            post :update, id: entry.id, starred: 'true', format: :js
          }.to change(StarredEntry, :count).by(1)

          expect(response.status).to eq 200
        end
      end

      context "already starred" do
        it "works" do
          user = create(:user, starred_feed_enabled: 1)
          sign_in user

          entry = create(:entry)
          StarredEntry.create_from_owners(user, entry)

          expect {
            post :update, id: entry.id, starred: 'true', format: :js
          }.not_to change(StarredEntry, :count)

          expect(response.status).to eq 200
        end
      end
    end

    context "with starred=false" do
      it "works" do
        user = create(:user, starred_feed_enabled: 1)
        sign_in user

        entry = create(:entry)
        StarredEntry.create_from_owners(user, entry)

        expect {
          post :update, id: entry.id, starred: 'false', format: :js
        }.to change(StarredEntry, :count).by(-1)

        expect(response.status).to eq 200
      end
    end
  end
end
