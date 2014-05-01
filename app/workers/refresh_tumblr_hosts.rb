class RefreshTumblrHosts
  include Sidekiq::Worker

  def perform(user_id)
    user = User.find(user_id)
    tumblr_hosts = []
    tumblr = @user.supported_sharing_services.where(service_id: 'tumblr').first
    if tumblr.present?
      info = tumblr.tumblr_info
      if info['response'].present?
        tumblr_hosts = info['response']['user']['blogs'].collect {|blog| URI.parse(blog['url']).host }
      end
    end
  end


end