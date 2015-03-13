class WebhookSend
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(supported_sharing_service_id, entry_id)
    supported_sharing_service = SupportedSharingService.find(supported_sharing_service_id)
    entry = Entry.find(entry_id)

    locals = {
      entry: entry,
      params: {
        include_content_diff: 'true',
        include_enclosure: 'true',
        include_original: 'true',
        include_feed: 'true'
      }
    }
    view_paths = Rails::Application::Configuration.new(Rails.root).paths["app/views"]
    action_view = ActionView::Base.new(view_paths)
    entry_json = action_view.render(partial: 'api/v2/entries/entry', locals: locals)

    options = {
      timeout: 10,
      verify: false,
      headers: {
        'Content-Type' => 'application/json'
      },
      query: {
        url: supported_sharing_service.webhook_url
      },
      body: entry_json
    }
    response = HTTParty.post('', options)
    response.body
  end
end