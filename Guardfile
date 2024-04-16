# Guardfile
guard :minitest, all_on_start: false do
  # Run everything within 'test' if the test helper changes
  watch(%r{^test/test_helper\.rb$}) { 'test' }

  # Run everything within 'test/system' if ApplicationSystemTestCase changes
  watch(%r{^test/application_system_test_case\.rb$}) { 'test/system' }

  # Run the corresponding test anytime something within 'app' changes
  #   e.g. 'app/models/example.rb' => 'test/models/example_test.rb'
  watch(%r{^app/(.+)\.rb$}) { |m| "test/#{m[1]}_test.rb" }

  # Run a test any time it changes
  watch(%r{^test/.+_test\.rb$})

  # Run everything in or below 'test/controllers' everytime
  #   ApplicationController changes
  # watch(%r{^app/controllers/application_controller\.rb$}) do
  #   'test/controllers'
  # end

  # Run integration test every time a corresponding controller changes
  # watch(%r{^app/controllers/(.+)_controller\.rb$}) do |m|
  #   "test/integration/#{m[1]}_test.rb"
  # end

  # Run mailer tests when mailer views change
  # watch(%r{^app/views/(.+)_mailer/.+}) do |m|
  #   "test/mailers/#{m[1]}_mailer_test.rb"
  # end
end