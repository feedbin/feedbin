ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'login_helper'
ActiveRecord::FixtureSet.context_class.send :include, LoginHelper

class ActiveSupport::TestCase
  include LoginHelper

  fixtures :all

  # Add more helper methods to be used by all tests here...
end
