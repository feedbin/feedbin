Rails.application.reloader.to_prepare do
  module Search
    def configure!
      exact_field = {
        exact: {
          type: "text",
          analyzer: "lower_exact"
        }
      }

      shared_settings = {
        index: {
          number_of_shards: Rails.env.local? ? "1" : "6",
          number_of_replicas: ENV.fetch("ELASTICSEARCH_REPLICAS", "0")
        },
        analysis: {
          analyzer: {
            lower_exact: {
              type: "custom",
              tokenizer: "whitespace",
              filter: ["lowercase"]
            },
            stemmed: {
              type: "custom",
              tokenizer: "standard",
              filter: ["lowercase", "asciifolding", "stemmer"]
            }
          }
        }
      }

      entries_mapping = {
        settings: shared_settings,
        mappings: {
          _source: {
            enabled: Rails.env.development? ? true : false
          },
          properties: {
            author: {
              analyzer: "stemmed",
              fields: exact_field,
              type: "text"
            },
            content: {
              analyzer: "stemmed",
              fields: exact_field,
              type: "text"
            },
            feed_id: {
              type: "keyword"
            },
            id: {
              type: "keyword"
            },
            link: {
              type: "keyword"
            },
            category: {
              type: "text",
              analyzer: "lower_exact"
            },
            published: {
              type: "date"
            },
            title: {
              analyzer: "stemmed",
              fields: exact_field,
              type: "text"
            },
            twitter_image: {
              type: "boolean"
            },
            twitter_link: {
              type: "boolean"
            },
            twitter_media: {
              type: "boolean"
            },
            twitter_name: {
              type: "text",
              analyzer: "stemmed",
              fields: exact_field
            },
            twitter_retweet: {
              type: "boolean"
            },
            twitter_screen_name: {
              type: "text",
              analyzer: "stemmed",
              fields: exact_field
            },
            updated: {
              type: "date"
            },
            url: {
              type: "text",
              analyzer: "lower_exact"
            },
            type: {
              type: "text",
              analyzer: "keyword"
            },
            media_duration: {
              type: "long"
            },
            word_count: {
              type: "long"
            }
          }
        }
      }

      feeds_mapping = {
        settings: shared_settings,
        mappings: {
          _source: {
            enabled: true
          },
          properties: {
            id: {
              type: "keyword"
            },
            title: {
              type: "text",
              analyzer: "stemmed"
            },
            site_url: {
              type: "text",
              analyzer: "lower_exact"
            },
            feed_url: {
              type: "text",
              analyzer: "lower_exact"
            },
            self_url: {
              type: "keyword"
            },
            description: {
              type: "text",
              analyzer: "stemmed"
            },
            author: {
              type: "text",
            },
            meta_title: {
              type: "text",
              analyzer: "stemmed"
            },
            meta_description: {
              type: "text",
              analyzer: "stemmed"
            },
            subscriptions_count: {
              type: "long",
            },
          }
        }
      }

      actions_mapping = {
        settings: shared_settings,
        mappings: {
          properties: entries_mapping[:mappings][:properties].merge({
            query: {
              type: "percolator"
            }
          })
        }
      }

      $search = {}.tap do |hash|
        hash[:servers] = {
          primary: ConnectionPool.new(size: ENV.fetch("DB_POOL", 1)) {
            Search::Connection.new(ENV.fetch("ELASTICSEARCH_URL", "http://localhost:9200"),
              username: ENV["ELASTICSEARCH_USERNAME"],
              password: ENV["ELASTICSEARCH_PASSWORD"]
            )
          }
        }

        if ENV["ELASTICSEARCH_ALT_URL"].present?
          hash[:servers][:secondary] = ConnectionPool.new(size: ENV.fetch("DB_POOL", 1)) {
            Search::Connection.new(ENV.fetch("ELASTICSEARCH_ALT_URL", "http://localhost:9200"),
              username: ENV["ELASTICSEARCH_ALT_USERNAME"],
              password: ENV["ELASTICSEARCH_ALT_PASSWORD"]
            )
          }
        end

        hash[:config] = {
          mappings: {
            entries: entries_mapping,
            actions: actions_mapping,
            feeds: feeds_mapping
          },
          aliases: {
            entries: "#{Search.index_name(Entry.table_name)}-01",
            actions: "#{Search.index_name(Action.table_name)}-01",
            feeds: "#{Search.index_name(Feed.table_name)}-01"
          }
        }
      end
    end
    module_function :configure!

    def client(mirror: false, &block)
      if mirror && $search[:servers][:secondary]
        $search[:servers][:secondary].with(&block)
      end
      $search[:servers][:primary].with(&block)
    end
    module_function :client

    # The alias each physical index is published under. Resolved at call time
    # rather than held in a constant: this module is defined inside a reloader
    # block, and naming the models at definition time would pin the classes
    # from whichever generation defined it.
    def index_targets
      {entries: Entry, actions: Action, feeds: Feed}
    end
    module_function :index_targets

    def setup
      index_targets.each do |key, model|
        index = $search[:config][:aliases][key]
        create_index(index, $search[:config][:mappings][key])
        publish_alias(index, Search.index_name(model.table_name))
      end
    rescue => exception
      log_search_error("Error initializing search: #{exception.inspect}")
    end
    module_function :setup

    # Connection#request hands back Elasticsearch's error body rather than
    # raising on it, so a failure here is only visible to a caller that reads
    # the response -- which is why the alias collision below went unnoticed
    # for so long. Re-PUTting an index that already exists is the normal case
    # on every boot after the first and stays quiet; anything else means the
    # index does not have the mapping this process thinks it does.
    def create_index(index, mapping)
      response = Search.client(mirror: true) { it.request(:put, index, json: mapping) }
      type = response.safe_dig("error", "type")
      return if type.nil? || type == "resource_already_exists_exception"
      log_search_error("Could not create index #{index}: #{response.safe_dig("error", "reason")}")
    end
    module_function :create_index

    # Elasticsearch refuses an alias whose name a concrete index already
    # holds. That is how a stray auto-created index shadows the real one: it
    # answers to the name the alias should have, carrying whatever dynamic
    # mapping it inferred from the first document written to it, so searches
    # that depend on the real mapping quietly return nothing. Test indexes
    # are disposable, so clear the squatter and alias properly. Anywhere else
    # it may hold real data, so report it and leave it alone.
    def publish_alias(index, alias_name)
      response = Search.client(mirror: true) { it.add_alias(index, alias_name: alias_name) }
      return unless response.safe_dig("error", "type") == "invalid_alias_name_exception"

      unless Rails.env.test?
        log_search_error("#{alias_name} is a concrete index, so #{index} cannot be published under it. Searches will read the index of that name instead until it is removed.")
        return
      end

      Search.client(mirror: true) { it.delete_index(alias_name) }
      Search.client(mirror: true) { it.add_alias(index, alias_name: alias_name) }
    end
    module_function :publish_alias

    def log_search_error(message)
      Rails.logger.error("---------------------------")
      Rails.logger.error(message)
      Rails.logger.error("---------------------------")
    end
    module_function :log_search_error
  end

  Search.configure!
end

unless Rails.env.production?
  Rails.application.config.after_initialize do
    Search.setup
  end
end

if Rails.env.development?
  ActiveSupport::Notifications.subscribe("request.search") do |name, start, finish, id, payload|
    Rails.logger.info(search: "request", method: payload.safe_dig(:response).request.verb, path: payload.safe_dig(:response).request.uri.to_s)
    json = JSON.pretty_generate(JSON.parse(payload.safe_dig(:response)&.request&.body&.source)) rescue nil
    Rails.logger.info(json)

    Rails.logger.info(search: "response", path: payload.safe_dig(:response).request.uri.to_s)

    json = JSON.pretty_generate(payload.safe_dig(:response)&.parse) rescue nil
    Rails.logger.info(json)
  end
end
