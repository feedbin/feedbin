class User < ApplicationRecord
  attr_accessor :stripe_token, :old_password_valid, :update_auth_token,
    :password_reset, :coupon_code, :is_trialing, :coupon_valid, :deleted

  has_secure_password

  store_accessor :settings,
    :entry_sort,
    :previous_read_count,
    :starred_feed_enabled,
    :precache_images,
    :show_unread_count,
    :sticky_view_inline,
    :mark_as_read_confirmation,
    :font_size,
    :font,
    :entry_width,
    :apple_push_notification_device_token,
    :mark_as_read_push_view,
    :keep_unread_entries,
    :receipt_info,
    :theme,
    :entries_display,
    :entries_feed,
    :entries_time,
    :entries_body,
    :entries_image,
    :ui_typeface,
    :update_message_seen,
    :hide_recently_read,
    :hide_updated,
    :view_mode,
    :disable_image_proxy,
    :api_client,
    :marketing_unsubscribe,
    :hide_recently_played,
    :now_playing_entry,
    :audio_panel_size,
    :view_links_in_app,
    :twitter_access_secret,
    :twitter_access_token,
    :twitter_screen_name,
    :twitter_access_error,
    :nice_frames,
    :favicon_colors,
    :newsletter_tag,
    :feeds_width,
    :entries_width

  has_one :coupon
  has_many :subscriptions, dependent: :delete_all
  has_many :feeds, through: :subscriptions
  has_many :entries, through: :feeds
  has_many :imports, dependent: :destroy
  has_many :billing_events, as: :billable, dependent: :delete_all
  has_many :taggings, dependent: :delete_all
  has_many :tags, through: :taggings
  has_many :sharing_services, dependent: :delete_all
  has_many :supported_sharing_services, dependent: :delete_all
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries, dependent: :delete_all
  has_many :saved_searches, dependent: :delete_all
  has_many :actions, dependent: :destroy
  has_many :recently_read_entries, dependent: :delete_all
  has_many :recently_played_entries, dependent: :delete_all
  has_many :updated_entries, dependent: :delete_all
  has_many :devices, dependent: :delete_all
  has_many :authentication_tokens, dependent: :delete_all
  has_many :in_app_purchases
  belongs_to :plan

  accepts_nested_attributes_for :sharing_services,
    allow_destroy: true,
    reject_if: ->(attributes) { attributes["label"].blank? || attributes["url"].blank? }

  after_initialize :set_defaults, if: :new_record?

  before_save :strip_email
  before_save :activate_subscriptions
  before_save { reset_auth_token }

  before_create :create_customer, unless: -> { !ENV["STRIPE_API_KEY"] }
  before_create { generate_token(:starred_token) }
  before_create { generate_token(:inbound_email_token, 4) }
  before_create { generate_newsletter_token }
  before_create { generate_token(:page_token) }

  before_update :update_billing, unless: -> { !ENV["STRIPE_API_KEY"] }
  before_destroy :cancel_billing, unless: -> { !ENV["STRIPE_API_KEY"] }
  before_destroy :create_deleted_user
  before_destroy :record_stats

  validate :changed_password, on: :update, unless: ->(user) { user.password_reset }
  validate :coupon_code_valid, on: :create, if: ->(user) { user.coupon_code }
  validate :plan_type_valid, on: :update
  validate :trial_plan_valid

  validates_presence_of :email
  validates_uniqueness_of :email, case_sensitive: false
  validates_presence_of :password, on: :create

  def newsletter_senders
    NewsletterSender.where(token: newsletter_authentication_token.token).order(name: :asc)
  end

  def generate_newsletter_token
    authentication_tokens.newsletters.new(length: 4)
  end

  def theme
    if settings
      if settings["theme"] == "night"
        "dusk"
      else
        settings["theme"]
      end
    end
  end

  def twitter_enabled?
    twitter_access_secret && twitter_access_token
  end

  def set_defaults
    self.expires_at = Feedbin::Application.config.trial_days.days.from_now
    self.update_auth_token = true
    self.mark_as_read_confirmation = 1
    self.font = "default"
    self.font_size = 5
    self.price_tier = Feedbin::Application.config.price_tier
  end

  def with_params(params)
    if params[:coupon_code].present?
      coupon = Coupon.find_by(coupon_code: params[:coupon_code])
      self.coupon_valid = coupon.present? && !coupon.redeemed
      self.coupon_code = params[:coupon_code]
    end

    if coupon_valid || !ENV["STRIPE_API_KEY"]
      self.free_ok = true
      self.plan = Plan.find_by_stripe_id("free")
    else
      self.plan = Plan.find_by_stripe_id("trial")
    end

    if params[:user] && params[:user][:password]
      self.password_confirmation = params[:user][:password]
    end
    self
  end

  def schedule_trial_jobs
    OnboardingMessage.perform_async(id, MarketingMailer.method(:onboarding_1_welcome).name.to_s)
    OnboardingMessage.perform_in(3.days, id, MarketingMailer.method(:onboarding_2_mobile).name.to_s)
    OnboardingMessage.perform_in(5.days, id, MarketingMailer.method(:onboarding_3_subscribe).name.to_s)
    OnboardingMessage.perform_in(Feedbin::Application.config.trial_days.days - 1.days, id, MarketingMailer.method(:onboarding_4_expiring).name.to_s)
    OnboardingMessage.perform_at(Feedbin::Application.config.trial_days.days.from_now + 1.days, id, MarketingMailer.method(:onboarding_5_expired).name.to_s)
  end

  def setting_on?(setting_symbol)
    send(setting_symbol) == "1"
  end

  def subscribed_to_emails?
    !setting_on?(:marketing_unsubscribe)
  end

  def activate_subscriptions
    if paid_conversion?
      subscriptions.update_all(active: true)
    end
  end

  def paid_conversion?
    plan_id_changed? && plan_id_was == Plan.find_by_stripe_id("trial").id
  end

  def strip_email
    email.strip!
  end

  def feed_tags
    @feed_tags ||= begin
      Tag.where(id: taggings.distinct.pluck(:tag_id)).natural_sort_by do |tag|
        tag.name
      end
    end
  end

  def tag_names
    feed_tags.each_with_object({}) do |tag, hash|
      hash[tag.id] = tag.name
    end
  end

  def coupon_code_valid
    coupon_record = Coupon.find_by_coupon_code(coupon_code)
    if !coupon_record || coupon_record.redeemed
      errors.add(:coupon_code, "is invalid")
    end
  end

  def free_ok
    @free_ok || plan_id_was == Plan.find_by_stripe_id("free").id
  end

  attr_writer :free_ok

  def plan_type_valid
    valid_plans = if free_ok
      Plan.all.pluck(:id)
    else
      Plan.where(price_tier: price_tier).where.not(stripe_id: "free").pluck(:id)
    end

    valid_plans.append(plan_id_was)

    unless valid_plans.include?(plan.id)
      errors.add(:plan_id, "is invalid")
    end
  end

  def available_plans
    plan_stripe_id = plan.stripe_id
    if plan_stripe_id == "trial"
      Plan.where(price_tier: price_tier, stripe_id: ["basic-monthly", "basic-yearly", "basic-monthly-2", "basic-yearly-2", "basic-monthly-3", "basic-yearly-3"]).order("price DESC")
    elsif plan_stripe_id == "free"
      Plan.where(price_tier: price_tier)
    else
      exclude = ["free", "trial", "timed"]
      Plan.where(price_tier: price_tier).where.not(stripe_id: exclude)
    end
  end

  def timed_plan_expired?
    timed_plan? && expires_at.past?
  end

  def timed_plan?
    plan.stripe_id == "timed"
  end

  def trial_plan_valid
    trial_plan = Plan.find_by_stripe_id("trial")
    if plan_id == trial_plan.id && plan_id_was != trial_plan.id && !plan_id_was.nil?
      errors.add(:plan_id, "is invalid")
    end
  end

  def changed_password
    if password_digest_changed? && !old_password_valid
      errors.add(:old_password, "is incorrect")
    end
  end

  def reset_auth_token
    if update_auth_token
      generate_token(:auth_token)
    end
  end

  def generate_token(column, length = nil, hash = false)
    begin
      random_string = SecureRandom.hex(length)
      self[column] = if hash
        Digest::SHA1.hexdigest(random_string)
      else
        random_string
      end
    end while User.exists?(column => self[column])
    random_string
  end

  def send_password_reset
    token = generate_token(:password_reset_token, nil, true)
    self.password_reset_sent_at = Time.now
    save!
    UserMailer.delay(queue: :critical).password_reset(id, token)
  end

  def create_customer
    @stripe_customer = Customer.create(email, plan.stripe_id, trial_end)
    self.customer_id = @stripe_customer.id
    if coupon_code
      coupon_record = Coupon.find_by_coupon_code(coupon_code)
      coupon_record.update(redeemed: true)
      self.coupon = coupon_record
    end
  end

  def update_billing
    if email_changed?
      stripe_customer.update_email(email)
    end

    if stripe_token.present?
      stripe_customer.update_source(stripe_token)
      self.suspended = false
      subscriptions.update_all(active: true)
    end

    if plan_id_changed?
      stripe_customer.update_plan(plan.stripe_id, trial_end)
    end

    self.stripe_token = nil
  rescue Stripe::StripeError => exception
    Honeybadger.notify(exception)
    errors.add :base, exception.message.to_s
    self.stripe_token = nil
    throw(:abort)
  end

  def stripe_customer
    @stripe_customer ||= Customer.retrieve(customer_id)
  end

  def cancel_billing
    customer = Stripe::Customer.retrieve(customer_id)
    customer.delete
  rescue Stripe::StripeError => e
    logger.error "Stripe Error: " + e.message
    errors.add :base, "#{e.message}."
    CancelBilling.perform_async(customer_id)
  end

  def tag_group
    unique_tags = feed_tags
    feeds_by_tag = build_feeds_by_tag
    feeds_by_id = feeds.includes(:favicon).include_user_title
    feeds_by_id = feeds_by_id.each_with_object({}) { |feed, hash|
      hash[feed.id] = feed
    }

    unique_tags.map do |tag|
      feed_ids = feeds_by_tag[tag.id] || []
      user_feeds = feeds_by_id.values_at(*feed_ids).compact
      tag.user_feeds = user_feeds.sort_by { |feed| feed.title.try(:downcase) }
      tag
    end

    unique_tags
  end

  def tags_on_feed
    names = tag_names
    build_tags_by_feed.each_with_object({}) do |(feed_id, tag_ids), hash|
      hash[feed_id] = tag_ids.map { |tag_id| names[tag_id] }
    end
  end

  def feed_order
    feeds.include_user_title.map { |feed| feed.id }
  end

  def subscribe!(feed)
    subscriptions.create!(feed_id: feed.id)
  end

  def subscribed_to?(feed_id)
    subscriptions.where(feed_id: feed_id).exists?
  end

  def self.search(query)
    where("email like ?", "%#{query}%")
  end

  def days_left
    now = Time.now.to_i
    seconds_left = trial_end.to_i - now
    days = (seconds_left.to_f / 86400.to_f).ceil
    days > 0 ? days : 0
  end

  def trial_end
    @trial_end ||= begin
      expires_at || Time.now + Feedbin::Application.config.trial_days.days
    end
  end

  def update_tag_visibility(tag, visible)
    tag_visibility_will_change!
    tag_visibility[tag] = visible
    update tag_visibility: tag_visibility
  end

  def build_feeds_by_tag
    query = <<-eos
      SELECT
        tag_id, array_to_json(array_agg(DISTINCT feed_id)) as feed_ids
      FROM
        taggings
      WHERE user_id = ? AND feed_id IN (?)
      GROUP BY tag_id
    eos
    query = ActiveRecord::Base.send(:sanitize_sql_array, [query, id, subscriptions.default.pluck(:feed_id)])
    results = ActiveRecord::Base.connection.execute(query)
    results.each_with_object({}) do |result, hash|
      hash[result["tag_id"].to_i] = JSON.parse(result["feed_ids"])
    end
  end

  def build_tags_by_feed
    query = <<-eos
      SELECT
        feed_id, array_to_json(array_agg(DISTINCT tag_id)) as tag_ids
      FROM
        taggings
      WHERE user_id = ? AND feed_id IN (?)
      GROUP BY feed_id
    eos
    query = ActiveRecord::Base.send(:sanitize_sql_array, [query, id, subscriptions.pluck(:feed_id)])
    results = ActiveRecord::Base.connection.execute(query)
    results.each_with_object({}) do |result, hash|
      hash[result["feed_id"].to_i] = JSON.parse(result["tag_ids"])
    end
  end

  def create_deleted_user
    DeletedUser.create(email: email, customer_id: customer_id)
  end

  def record_stats
    if plan.stripe_id == "trial"
      Librato.increment("user.trial.cancel")
    else
      Librato.increment("user.paid.cancel")
    end
  end

  def activate
    update(suspended: false)
    subscriptions.update_all(active: true)
  end

  def deactivate
    update(suspended: true)
    subscriptions.update_all(active: false)
  end

  def active?
    !suspended
  end

  def admin?
    admin
  end

  def newsletter_address
    "#{newsletter_authentication_token.token}@newsletters.feedbin.com"
  end

  def newsletter_authentication_token
    authentication_tokens.newsletters.active.take
  end

  def stripe_url
    "https://manage.stripe.com/customers/#{customer_id}"
  end

  def deleted?
    deleted || false
  end

  def can_read_feed?(feed)
    can_read = false
    if feed.respond_to?(:id)
      feed = feed.id
    end

    if subscribed_to?(feed)
      can_read = true
    end

    if !can_read && starred_entries.where(feed_id: feed).exists?
      can_read = true
    end

    can_read
  end

  def can_read_entry?(entry_id)
    can_read = false

    entry = Entry.find(entry_id)

    if subscribed_to?(entry.feed)
      can_read = true
    end

    if !can_read && starred_entries.where(entry: entry).exists?
      can_read = true
    end

    if !can_read && recently_read_entries.where(entry: entry).exists?
      can_read = true
    end

    if !can_read && recently_played_entries.where(entry: entry).exists?
      can_read = true
    end

    can_read
  end

  def combined_sharing_services
    (sharing_services + supported_sharing_services)
      .select  { |sharing_service| sharing_service.active?    }
      .sort_by { |sharing_service| sharing_service.label      }
      .map     { |sharing_service| sharing_service.share_link }
      .compact
  end

  def can_read_filter(requested_ids)
    allowed_ids = []

    feed_ids = subscriptions.pluck(:feed_id)

    ids = Entry.where(feed_id: feed_ids, id: requested_ids).pluck(:id)
    allowed_ids = allowed_ids.push(ids).flatten

    if requested_ids.length != allowed_ids.length
      ids = starred_entries.where(entry_id: requested_ids).pluck(:entry_id)
      allowed_ids = allowed_ids.push(ids).flatten
    end

    if requested_ids.length != allowed_ids.length
      ids = recently_read_entries.where(entry_id: requested_ids).pluck(:entry_id)
      allowed_ids = allowed_ids.push(ids).flatten
    end

    if requested_ids.length != allowed_ids.length
      ids = recently_played_entries.where(entry_id: requested_ids).pluck(:entry_id)
      allowed_ids = allowed_ids.push(ids).flatten
    end

    allowed_ids.uniq
  end

  def trialing?
    plan == Plan.find_by_stripe_id("trial")
  end

  def has_tweet?(main_tweet_id)
    entries.where(main_tweet_id: main_tweet_id).limit(2).count > 1
  end

  def twitter_credentials_valid?
    twitter_client.verify_credentials && true
  rescue Twitter::Error::Unauthorized
    false
  end

  def recently_played_entries_progress
    recently_played_entries.select(:duration, :progress, :entry_id).each_with_object({}) do |item, hash|
      hash[item.entry_id] = {progress: item.progress, duration: item.duration}
    end
  end

  def twitter_auth
    if twitter_enabled?
      TwitterAuth.new(screen_name: twitter_screen_name, token: twitter_access_token, secret: twitter_access_secret)
    else
      nil
    end
  end

  def twitter_log_out
    update(
      twitter_access_token: nil,
      twitter_access_secret: nil,
      twitter_screen_name: nil,
      twitter_auth_failures: nil
    )
  end

  def twitter_client
    if twitter_enabled?
      @twitter_client ||= ::Twitter::REST::Client.new { |config|
        config.consumer_key = ENV["TWITTER_KEY"]
        config.consumer_secret = ENV["TWITTER_SECRET"]
        config.access_token = twitter_access_token
        config.access_token_secret = twitter_access_secret
      }
    end
  end
end
