# Regression checks for dead_methods.rb on the cleanup branch. Each entry was
# verified by hand. Run after the finder:
#
#   ruby doc/plans/unused-code-sweep/bin/dead_methods_expectations.rb
#
# MUST_KEEP: live code that an earlier version of the finder flagged by mistake.
# None may appear in a strong bucket (1-5 or a namespace bucket).
# MUST_FIND: verified dead code; each must appear in a strong bucket, or be
# deleted already (its def no longer in the listed file).
require "minitest/autorun"

OUT = File.expand_path("../../../../tmp/dead_methods", __dir__)

MUST_KEEP = {
  "SubscriptionPresenter#sparkline" => "called as subscription_presenter.sparkline in settings/subscriptions/shared/subscription.rb",
  "SidekiqHelper::ClassMethods#local_queue" => "extended into jobs by include SidekiqHelper; called in class bodies",
  "ActionsHelper#action_label" => "called inside its own module (helpers are included into view classes Rails builds later)",
  "Image.as_text" => "called as ::Image.as_text from ImageCrawler::MicropostAvatar",
  "Image.stored_object_attributes" => "called as ::Image.stored_object_attributes from ImageCrawler",
  "JsonConverter.dump" => "store coder: ActiveRecord calls dump/load",
  "MercuryParser#marshal_dump" => "Marshal hook",
  "OnboardingMessage#onboarding_1_welcome" => "called with send(@message) from job arguments"
}.freeze

# Reopened framework/core classes and live namespaces: never in namespaces.tsv.
MUST_KEEP_NAMESPACES = %w[NilClass Enumerable Delegator ActionController::ConditionalGet SidekiqHelper FeedCrawler].freeze

MUST_FIND = {
  "UpdatedEntry.create_from_owners" => "app/models/updated_entry.rb",
  "SettingsHelper#get_tag_names" => "app/helpers/settings_helper.rb",
  "EntriesHelper#entries_cache_key" => "app/helpers/entries_helper.rb",
  "RecentlyPlayedEntriesController#queued_entry_params" => "app/controllers/recently_played_entries_controller.rb"
}.freeze

MUST_FIND_NAMESPACES = {"Subscriptions::NewView" => "app/views/subscriptions/new_view.rb"}.freeze

ROOT = File.expand_path("../../../..", __dir__)

# True once the def is gone from its file (the cleanup branch deleted it).
def deleted?(label, file)
  path = File.join(ROOT, file)
  return true unless File.exist?(path)
  name = Regexp.escape(label.split(/[#.]/).last)
  pattern = label.include?("#") ? /^\s*def #{name}[\s(]/ : /^\s*def self\.#{name}[\s(]/
  !File.read(path).match?(pattern)
end

class DeadMethodsExpectations < Minitest::Test
  STRONG = /\A[1-5]-/

  def rows(file) = File.readlines(File.join(OUT, file), chomp: true).drop(1).map { it.split("\t") }
  def strong_methods = rows("candidates.tsv").select { it[0].match?(STRONG) }.to_h { [it[1], it[0]] }
  def namespaces = rows("namespaces.tsv").map { it[1] }

  def test_live_code_is_not_flagged
    flagged = MUST_KEEP.keys.select { strong_methods.key?(it) }
    assert_empty flagged, flagged.map { "#{it} (#{strong_methods[it]}): #{MUST_KEEP[it]}" }.join("\n")
    assert_empty MUST_KEEP_NAMESPACES & namespaces
  end

  def test_verified_dead_code_is_found
    missing = MUST_FIND.reject { |label, file| strong_methods.key?(label) || deleted?(label, file) }.keys +
      MUST_FIND_NAMESPACES.reject { |name, file| namespaces.include?(name) || !File.exist?(File.join(ROOT, file)) }.keys
    assert_empty missing
  end
end
