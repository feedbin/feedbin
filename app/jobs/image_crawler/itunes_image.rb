module ImageCrawler
  class ItunesImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(public_id, image = nil)
      public_id = public_id.split("-").first
      @entry = Entry.find_by_public_id(public_id)
      @image = image

      if @image
        receive
      else
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      Pipeline::Find.perform_async("#{@entry.public_id}-itunes", "podcast", [@entry.rebase_url(@entry.data["itunes_image"])])
    end

    def receive
      @entry.update(media_image: @image["processed_url"])
    end
  end
end