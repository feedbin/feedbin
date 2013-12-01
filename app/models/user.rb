class User < ActiveRecord::Base

  attr_accessor :stripe_token, :old_password_valid, :update_auth_token, :password_reset, :coupon_code, :free_ok, :is_trialing

  has_secure_password

  store_accessor :settings, :entry_sort, :previous_read_count, :starred_feed_enabled,
                 :hide_tagged_feeds, :precache_images, :show_unread_count, :sticky_view_inline,
                 :mark_as_read_confirmation, :font_size, :font, :entry_width, :apple_push_notification_device_token,
                 :mark_as_read_push_view, :keep_unread_entries, :receipt_info

  has_one :coupon
  has_many :subscriptions, dependent: :delete_all
  has_many :feeds, through: :subscriptions
  has_many :entries, through: :feeds
  has_many :imports, dependent: :destroy
  has_many :billing_events, as: :billable, dependent: :delete_all
  has_many :taggings, dependent: :delete_all
  has_many :tags, through: :taggings
  has_many :sharing_services, dependent: :delete_all
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries, dependent: :delete_all
  has_many :saved_searches, dependent: :delete_all
  has_many :actions, dependent: :destroy
  belongs_to :plan

  accepts_nested_attributes_for :sharing_services,
                                allow_destroy: true,
                                reject_if: -> attributes { attributes['label'].blank? || attributes['url'].blank? }

  accepts_nested_attributes_for :actions, allow_destroy: true, reject_if: :all_blank

  before_save :update_billing, unless: -> user { user.admin || !ENV['STRIPE_API_KEY'] }
  before_destroy :cancel_billing, unless: -> user { user.admin }
  before_save :strip_email
  before_save :activate_subscriptions
  before_save { reset_auth_token }
  before_create { generate_token(:starred_token) }
  before_create { generate_token(:inbound_email_token) }

  validates_presence_of :password, on: :create
  validates_presence_of :email
  validates_uniqueness_of :email, case_sensitive: false
  validate :changed_password, on: :update, unless: -> user { user.password_reset }
  validate :coupon_code_valid, on: :create, if: -> user { user.coupon_code }
  validate :plan_type_valid
  validate :trial_plan_valid

  def to_param
    email
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

  def plan_type_valid
    if free_ok
      valid_plans = Plan.where(price_tier: plan.price_tier).pluck(:id)
    else
      valid_plans = Plan.where(price_tier: plan.price_tier).where.not(stripe_id: 'free').pluck(:id)
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

  def generate_token(column)
    begin
      self[column] = SecureRandom.urlsafe_base64
    end while User.exists?(column => self[column])
  end

  def send_password_reset
    generate_token(:password_reset_token)
    self.password_reset_sent_at = Time.now
    save!
    UserMailer.delay(queue: :critical).password_reset(id)
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

  def total_unread
    @total_unread_count ||= unread_count.inject(0) {|sum, (feed_id, count)| sum += count}
  end

  def total_starred
    starred_entries.count
  end

  def title_with_count
    if self.show_unread_count == '1'
      @title_count ||= unread_entries.limit(1000).count
      if @title_count == 0
        "Feedbin"
      elsif @title_count >= 1_000
        "Feedbin (1,000+)"
      else
        "Feedbin (#{@title_count.to_s})"
      end
    else
      "Feedbin"
    end
  end

  # TODO make sure zero counts get hidden, maybe load feeds based on this list
  def unread_count
    @count ||= unread_entries.group(:feed_id).count
  end

  def feed_entries_count
    ids = {}
    feeds.pluck('feeds.id').map {|id| ids[id] = 0 }
    ids.merge(entries.group('entries.feed_id').count)
  end

  def feed_with_subscription_id(feed_id)
    feeds.select("feeds.*, subscriptions.id as subscription_id").where("feeds.id = ? AND subscriptions.user_id = #{self.id}", feed_id).first
  end

  def feeds_list(view_mode)
    list = feeds.order("lower(feeds.title) ASC")
    feed_count(view_mode, list)
  end

  def feed_count(view_mode, user_feeds, selected_item = nil, keep_selected = false)
    counts = unread_count
    user_feeds.map do |feed|
      feed.unread_count = counts[feed.id] || 0
      feed
    end
    if selected_item =~ /feed_/
      selected_item = selected_item.sub('feed_', '').to_i
    end
    if 'view_unread' == view_mode
      user_feeds = user_feeds.reject {|feed|
        if keep_selected && feed.id == selected_item
          false
        else
          feed.unread_count == 0
        end
      }
    end
    user_feeds
  end

  def owned_tags_with_count(view_mode, selected_item = nil, keep_selected = false)
    taggings = feed_tags
    counts = unread_count
    if selected_item =~ /tag_/
      selected_tag = selected_item.sub('tag_', '').to_i
    else
      selected_tag = nil
    end
    taggings.each do |tag|
      feed_ids = Tagging.where(tag_id: tag, user_id: self, feed_id: subscriptions.pluck(:feed_id)).pluck(:feed_id)
      tag.unread_count = feed_ids.inject(0) { |sum, feed_id|
        count = counts[feed_id] || 0
        sum + count
      }
      list = feeds.where(id: feed_ids).include_user_title
      tag.user_feeds = feed_count(view_mode, list, selected_item, true)
    end
    if 'view_unread' == view_mode
      taggings = taggings.reject {|tag|
        if selected_item && tag.id == selected_tag || tag.user_feeds.any?
          false
        else
          tag.unread_count == 0
        end
      }
    end
    taggings
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
    subscriptions.where(feed_id: feed_id).present?
  end

  def self.search(query)
    where("email like ?", "%#{query}%")
  end

  def days_left
    expires = (self.created_at + Feedbin::Application.config.trial_days.days).to_i
    now = Time.now.to_i
    seconds_left = expires - now
    (seconds_left.to_f / 86400.to_f).ceil
  end

end
