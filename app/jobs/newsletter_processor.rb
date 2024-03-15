class NewsletterProcessor
  include Sidekiq::Worker
  sidekiq_options queue: :network_default

  def perform(to, url)
    url = Addressable::URI.parse(url)
    path = url.path.delete_prefix("/")
    to = Mail::Address.new(to)
    token = EmailNewsletter.token(to.local)

    if AuthenticationToken.newsletters.active.where(token: token).exists?
      message = client.get_object(url.host, path)
      NewsletterReceiver.new.perform(to.local, message.body)
    end

    client.delete_object(url.host, path)
  end

  private

  def client
    @client ||= begin
      Fog::Storage.new(STORAGE)
    end
  end
end
