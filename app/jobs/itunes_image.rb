class ItunesImage
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(entry_id, original_url = nil, processed_url = nil)
    @entry = Entry.find(entry_id)
    @entry_id = entry_id
    @original_url = original_url
    @processed_url = processed_url
    if @processed_url
      receive
    else
      schedule
    end
  rescue ActiveRecord::RecordNotFound
  end

  def schedule
    Sidekiq::Client.push(
      "args" => [@entry_id, @original_url, @entry.public_id],
      "class" => "ItunesImage",
      "queue" => "images",
      "retry" => false,
    )
  end

  def receive
    entry = Entry.find(@entry_id)
    data = entry.data || {}
    data["itunes_image_processed"] = @processed_url
    entry.update(data: data)
  end
end
