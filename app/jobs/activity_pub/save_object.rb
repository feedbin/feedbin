module ActivityPub
  class SaveObject
    include Sidekiq::Worker
    include ActivityHelper
    sidekiq_options queue: :crawl_critical, retry: false
    def perform(url)
      activity = Activity.find_by(url: url)
      if activity.nil?
        response = HTTP.accept(AutoDiscovery::CONTENT_TYPE).get(url).parse
        type = response.dig("type")
        return if type.nil?
        activity = Activity.create!(activity_type: type, url: url, data: response)
      end

      if attributed_to = activity.data.dig("attributedTo")
        attributed_url = value_or_id(first_of_value(attributed_to))
        self.class.new.perform(attributed_url)
      end
    end
  end
end