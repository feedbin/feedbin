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

  # Closing the account between requesting an export and the job running is the
  # ordinary way this fails. The tempfile does not exist yet at that point, so
  # an unguarded ensure raises over the top of RecordNotFound and the failure
  # arrives in the error tracker as an unexplained crash instead.
  test "a deleted account fails as RecordNotFound" do
    assert_raises(ActiveRecord::RecordNotFound) do
      StarredEntriesExport.new.perform(0)
    end
  end

  test "exports an empty array when the account has nothing starred" do
    user = users(:ben)
    StarredEntry.where(user: user).delete_all
    exported = nil

    StarredEntriesExport.new.tap do |job|
      job.define_singleton_method(:upload_file) do |file|
        exported = File.read(file)
        Faker::Internet.url
      end
      job.perform(user.id)
    end

    assert_equal [], JSON.parse(exported)
  end

  test "exports an empty array when every starred entry has aged out" do
    user = users(:ben)
    entry = create_entry(user.feeds.first)
    StarredEntry.create_from_owners(user, entry)
    entry.destroy
    exported = nil

    StarredEntriesExport.new.tap do |job|
      job.define_singleton_method(:upload_file) do |file|
        exported = File.read(file)
        Faker::Internet.url
      end
      job.perform(user.id)
    end

    assert_equal [], JSON.parse(exported)
  end
end
