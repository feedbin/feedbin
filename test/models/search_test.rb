require "test_helper"

class SearchTest < ActiveSupport::TestCase
  test "prefixes the base name in the test environment" do
    with_test_worker(nil) do
      assert_equal "test-entries", Search.index_name("entries")
    end
  end

  test "includes the parallel worker number when TEST_WORKER is set" do
    with_test_worker("3") do
      assert_equal "test-3-entries", Search.index_name("entries")
    end
  end

  test "returns the base name unchanged outside the test environment" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert_equal "entries", Search.index_name("entries")
    end
  end

  test "the search alias config is namespaced for the test environment" do
    prefix = ["test", ENV["TEST_WORKER"]].compact.join("-")
    assert_equal "#{prefix}-entries-01", $search[:config][:aliases][:entries]
    assert_equal "#{prefix}-actions-01", $search[:config][:aliases][:actions]
    assert_equal "#{prefix}-feeds-01", $search[:config][:aliases][:feeds]
  end

  test "configure! rebuilds the search config from the current environment" do
    with_test_worker("99") do
      Search.configure!
      assert_equal "test-99-entries-01", $search[:config][:aliases][:entries]
      assert_equal "test-99-actions-01", $search[:config][:aliases][:actions]
      assert_equal "test-99-feeds-01", $search[:config][:aliases][:feeds]
    end
  ensure
    Search.configure!
  end

  # Elasticsearch auto-creates an index the first time a document is written
  # to a name that does not exist yet. When that name is one of our aliases,
  # the resulting index answers to it forever after -- an alias cannot be
  # created over a concrete index of the same name -- and every read and
  # write lands on its inferred dynamic mapping instead of the one setup
  # installs. Searches that depend on the real mapping (title.exact, the
  # actions percolator) then return nothing at all, with no error anywhere.
  #
  # Runs in a namespace of its own so it cannot disturb the indexes the rest
  # of this worker's tests are using.
  test "setup reclaims an alias name that a concrete index has taken over" do
    with_test_worker("squatter") do
      Search.configure!
      index      = $search[:config][:aliases][:entries]
      alias_name = Search.index_name(Entry.table_name)

      Search.client { it.request(:post, "/#{alias_name}/_doc/1", params: {refresh: "true"}, json: {title: "auto-created"}) }
      assert_equal [], Search.client { it.get_indexes_from_alias(alias_name) },
        "precondition: the squatter answers to the alias name but is not an alias"

      Search.setup

      assert_equal [index], Search.client { it.get_indexes_from_alias(alias_name) },
        "setup should have dropped the squatter and published #{index} under #{alias_name}"

      mapping = Search.client { it.request(:get, "/#{alias_name}/_mapping") }
      assert mapping.safe_dig(index, "mappings", "properties", "title", "fields", "exact"),
        "the reclaimed index should carry our mapping, not an inferred one"
    ensure
      # setup builds all three namespaces, not just the one under test, so
      # clean up all of them: the physical indexes first (which takes their
      # aliases with them), then any name left holding a squatter of its own.
      $search[:config][:aliases].each_value do |name|
        Search.client { it.delete_index(name) }
      end
      [Entry, Action, Feed].each do |model|
        Search.client { it.delete_index(Search.index_name(model.table_name)) }
      end
    end
  ensure
    Search.configure!
  end

  private

  def with_test_worker(number)
    original = ENV["TEST_WORKER"]
    ENV["TEST_WORKER"] = number
    yield
  ensure
    original.nil? ? ENV.delete("TEST_WORKER") : ENV["TEST_WORKER"] = original
  end
end
