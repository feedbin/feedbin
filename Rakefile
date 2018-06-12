# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require File.expand_path('../config/application', __FILE__)

require 'coveralls/rake/task'

Coveralls::RakeTask.new

Feedbin::Application.load_tasks

task run_all_tests: [:test, :'test:system', :'coveralls:push']
