module ImageCrawler
  class TwitterProfileImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(twitter_user_id, image = nil)
      twitter_user_id = twitter_user_id.to_s.split("-").first
      @twitter_user = TwitterUser.find(twitter_user_id)
      @image = image
      @image ? receive : schedule
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      name = Digest::SHA1.hexdigest(@twitter_user.profile_image)

      unless @twitter_user.profile_image_url&.include?(name)
        Pipeline::Find.perform_async("#{@twitter_user.id}-#{name}", "profile", [@twitter_user.profile_image])
      end
    end

    def receive
      @twitter_user.update(profile_image_url: @image["processed_url"])
    end
  end
end