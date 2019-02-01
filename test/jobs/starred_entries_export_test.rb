require "test_helper"

class StarredEntriesExportTest < ActiveSupport::TestCase
  test "should send email" do
    user = users(:ben)
    entry = create_entry(user.feeds.first)
    StarredEntry.create_from_owners(user, entry)

    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      StarredEntriesExport.new.tap do |job|
        def job.upload_file(file)
          JSON.parse(File.open(file).read)
          Faker::Internet.url
        end
        job.perform(user.id)
      end
    end
  end
end
