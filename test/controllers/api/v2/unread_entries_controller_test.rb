require 'test_helper'

module Api
  module V2
    class UnreadEntriesControllerTest < ActionController::TestCase

      test "should get unread entries" do
        @request.headers['Authorization'] = basic_auth
        get :index, format: :json
        unread_entries_response = JSON.parse(response.body)
        assert_operator unread_entries_response.length, :>, 0
      end

      test "should create unread entries" do
        UnreadEntry.where(entry_id: 3).delete_all
        @request.headers['Authorization'] = basic_auth
        @request.headers['Content-Type'] = "application/json; charset=utf-8"
        assert_difference 'UnreadEntry.count' do
          post :create, unread_entries: [3], format: :json
        end
      end

      test "should destroy unread entries" do
        @request.headers['Authorization'] = basic_auth
        assert_difference 'UnreadEntry.count', -1 do
          post :destroy, unread_entries: [4], format: :json
        end
      end

    end
  end
end