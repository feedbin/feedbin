ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

class ActiveSupport::TestCase
  ActiveRecord::Migration.check_pending!
  load "#{Rails.root}/db/seeds_test.rb"

  def basic_auth
    ActionController::HttpAuthentication::Basic.encode_credentials('ben@benubois.com', 'passw0rd')
  end
end
