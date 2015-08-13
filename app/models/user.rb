class User < ActiveRecord::Base

  attr_accessor :stripe_token, :old_password_valid, :update_auth_token, :password_reset, :coupon_code, :is_trialing

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
                 :favicon_hash,
                 :entries_display,
                 :entries_feed,
                 :entries_time,
                 :entries_body,
                 :ui_typeface,
                 :update_message_seen,
                 :hide_recently_read,
                 :hide_updated,
                 :view_mode,
                 :disable_image_proxy

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
  has_many :updated_entries, dependent: :delete_all
  has_many :devices, dependent: :delete_all
  has_many :in_app_purchases
  belongs_to :plan

  accepts_nested_attributes_for :sharing_services,
                                allow_destroy: true,
                                reject_if: -> attributes { attributes['label'].blank? || attributes['url'].blank? }


  after_initialize :set_defaults, if: :new_record?

  before_save :update_billing, unless: -> user { user.admin || !ENV['STRIPE_API_KEY'] }
  before_save :strip_email
  before_save :activate_subscriptions
  before_save { reset_auth_token }

  before_create { generate_token(:starred_token) }
  before_create { generate_token(:inbound_email_token) }

  before_destroy :cancel_billing, unless: -> user { user.admin }
  before_destroy :create_deleted_user

  validate :changed_password, on: :update, unless: -> user { user.password_reset }
  validate :coupon_code_valid, on: :create, if: -> user { user.coupon_code }
  validate :plan_type_valid, on: :update
  validate :trial_plan_valid

  validates_presence_of :email
  validates_uniqueness_of :email, case_sensitive: false
  validates_presence_of :password, on: :create

  def set_defaults
    self.expires_at = Feedbin::Application.config.trial_days.days.from_now
    self.update_auth_token = true
    self.mark_as_read_confirmation = 1
    self.theme = "sunset"
    self.font = "serif-2"
    self.font_size = 7
  end

  def get_view_mode
    view_mode || "view_unread"
  end

  def get_favicon_hash
    if favicon_hash
      "#{favicon_hash}2"
    else
      "none"
    end
  end

  def setting_on?(setting_symbol)
    self.send(setting_symbol) == '1'
  end

  def activate_subscriptions
    if plan_id_changed? && plan_id_was == Plan.find_by_stripe_id('trial').id
      subscriptions.update_all(active: true)
    end
  end

  def strip_email
    self.email.strip!
  end

  def feed_tags
    tags.where(id: taggings.pluck(:tag_id)).order(:name).uniq
  end

  def coupon_code_valid
    coupon_record = Coupon.find_by_coupon_code(coupon_code)
    if !coupon_record || coupon_record.redeemed
      errors.add(:coupon_code, "is invalid")
    end
  end

  def free_ok
    @free_ok || plan_id_was == Plan.find_by_stripe_id('free').id
  end

  def free_ok=(value)
    @free_ok = value
  end

  def plan_type_valid
    original_plan = Plan.find(plan_id_was)
    if free_ok
      valid_plans = Plan.where(price_tier: original_plan.price_tier).pluck(:id)
    else
      valid_plans = Plan.where(price_tier: original_plan.price_tier).where.not(stripe_id: 'free').pluck(:id)
    end

    unless valid_plans.include?(plan.id)
      errors.add(:plan_id, 'is invalid')
    end
  end

  def trial_plan_valid
    trial_plan = Plan.find_by_stripe_id('trial')
    if plan_id == trial_plan.id && plan_id_was != trial_plan.id && !plan_id_was.nil?
      errors.add(:plan_id, 'is invalid')
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

  def generate_token(column, hash = false)
    begin
      random_string = SecureRandom.urlsafe_base64
      if hash
        self[column] = Digest::SHA1.hexdigest(random_string)
      else
        self[column] = random_string
      end
    end while User.exists?(column => self[column])
    random_string
  end

  def send_password_reset
    token = generate_token(:password_reset_token, true)
    self.password_reset_sent_at = Time.now
    save!
    UserMailer.delay(queue: :critical).password_reset(id, token)
  end

  def update_billing
    if customer_id.nil?
      customer = Stripe::Customer.create({email: email, plan: plan.stripe_id})
      if coupon_code
        coupon_record = Coupon.find_by_coupon_code(coupon_code)
        coupon_record.redeemed = true
        coupon_record.save
        self.coupon = coupon_record
      end
    else
      if email_changed? || stripe_token.present? || plan_id_changed?
        customer = Stripe::Customer.retrieve(customer_id)
        if stripe_token.present?
          customer.card = stripe_token
          self.suspended = false
          subscriptions.update_all(active: true)
        end
        customer.plan = plan.stripe_id
        customer.email = email
        customer.save
      end
    end
    unless customer.nil?
      self.last_4_digits = customer.try(:active_card).try(:last4)
      self.customer_id = customer.id
      self.stripe_token = nil
    end
  rescue Stripe::StripeError => e
    logger.error "Stripe Error: " + e.message
    errors.add :base, "#{e.message}."
    self.stripe_token = nil
    false
  end

  def cancel_billing
    customer = Stripe::Customer.retrieve(customer_id)
    customer.cancel_subscription
    customer.delete
  rescue Stripe::StripeError => e
    logger.error "Stripe Error: " + e.message
    errors.add :base, "#{e.message}."
    CancelBilling.perform_async(customer_id)
  end

  def feed_with_subscription_id(feed_id)
    feeds.select("feeds.*, subscriptions.id as subscription_id").where("feeds.id = ? AND subscriptions.user_id = #{self.id}", feed_id).first
  end

  def tag_group
    unique_tags = feed_tags
    feeds_by_tag = build_feeds_by_tag
    feeds_by_id = feeds.include_user_title
    feeds_by_id = feeds_by_id.each_with_object({}) do |feed, hash|
      hash[feed.id] = feed
    end

    unique_tags.map do |tag|
      feed_ids = feeds_by_tag[tag.id] || []
      user_feeds = feeds_by_id.values_at(*feed_ids).compact
      tag.user_feeds = user_feeds.sort_by { |feed| feed.title.try(:downcase) }
      tag
    end

    unique_tags
  end

  def feed_order
    feeds.include_user_title.map {|feed| feed.id}
  end

  def subscribe!(feed)
    subscriptions.create!(feed_id: feed.id)
  end

  def safe_subscribe(feed)
    if subscribed_to?(feed.id)
      subscriptions.where(feed_id: feed.id).first
    else
      subscribe!(feed)
    end
  end

  def subscribed_to?(feed_id)
    subscriptions.where(feed_id: feed_id).exists?
  end

  def self.search(query)
    where("email like ?", "%#{query}%")
  end

  def days_left
    expires = (self.created_at + Feedbin::Application.config.trial_days.days).to_i
    now = Time.now.to_i
    seconds_left = expires - now
    days = (seconds_left.to_f / 86400.to_f).ceil
    (days > 0) ? days : 0
  end

  def update_tag_visibility(tag, visible)
    tag_visibility_will_change!
    self.tag_visibility[tag] = visible
    update_attributes tag_visibility: self.tag_visibility
  end

  def build_feeds_by_tag
    query = <<-eos
      SELECT
        tag_id, array_to_json(array_agg(feed_id)) as feed_ids
      FROM
        taggings
      WHERE user_id = ? AND feed_id IN (?)
      GROUP BY tag_id
    eos
    query = ActiveRecord::Base.send(:sanitize_sql_array, [query, self.id, subscriptions.pluck(:feed_id)])
    results = ActiveRecord::Base.connection.execute(query)
    results.each_with_object({}) do |result, hash|
      hash[result['tag_id'].to_i] = JSON.parse(result['feed_ids'])
    end
  end

  def create_deleted_user
    DeletedUser.create(email: self.email, customer_id: self.customer_id)
  end

  def activate
    update_attributes(suspended: false)
    subscriptions.update_all(active: true)
  end

  def deactivate
    update_attributes(suspended: true)
    subscriptions.update_all(active: false)
  end

end
