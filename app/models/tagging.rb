class Tagging < ActiveRecord::Base
  belongs_to :tag
  belongs_to :feed
  belongs_to :user

  before_create :expire_entry_cache
  before_destroy :expire_entry_cache

  def expire_entry_cache
    set_key = FeedbinUtils.redis_key_set(self.user_id)
    keys = $redis.smembers(set_key) + [set_key]
    $redis.del(keys)
  end

end
