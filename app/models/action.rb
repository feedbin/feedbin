class Action < ActiveRecord::Base
    attr_accessor :include_all_feeds
    belongs_to :user
end
