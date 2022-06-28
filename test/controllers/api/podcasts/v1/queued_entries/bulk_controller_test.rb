require "test_helper"
class Api::Podcasts::V1::QueuedEntries::BulkControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feed = @user.podcast_subscriptions.first.feed
    create_entry(@feed)
    create_entry(@feed)
  
    @queued_entries = @user.queued_entries
  end

  test "should update multiple" do
    api_content_type
    login_as @user

    progress = 10

    queued_entries = @queued_entries.map do |queued_entry|
      {id: queued_entry.entry_id, progress: progress, progress_updated_at: Time.now.iso8601(6)}
    end

    patch :update, params: {queued_entries: queued_entries}, format: :json
    assert_response :success

    assert @queued_entries.first.reload.progress, progress
    assert @queued_entries.last.reload.progress, progress
  end

end
