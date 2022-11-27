module ActivityPub
  class ExpandActivity
    include Sidekiq::Worker
    sidekiq_options queue: :crawl_critical, retry: false
    def perform(activity)
      object = activity.dig("object")
      if object.is_a?(String)
        SaveObject.new.perform(object)
      end
    end
  end
end