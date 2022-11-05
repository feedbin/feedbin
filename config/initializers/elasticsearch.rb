require "net/http/persistent"

Rails.application.reloader.to_prepare do
  defaults = {
    log: Rails.env.development?,
    transport_options: {
      ssl: {verify: false}
    }
  }

  exact_field = {
    exact: {
      type: "text",
      analyzer: "lower_exact"
    }
  }

  shared_settings = {
    index: {
      number_of_shards: "6",
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
          filter: ["lowercase", "asciifolding", "english_stemmer"]
        }
      },
      filter: {
        english_stemmer: {
          type: "stemmer",
          name: "english"
        }
      }
    }
  }

  entries_mapping = {
    settings: shared_settings,
    mappings: {
      # _source: {
      #   enabled: false
      # },
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
    hash[:main] = Elasticsearch::Client.new(defaults)
    hash[:alt]  = Elasticsearch::Client.new(defaults.merge(url: ENV["ELASTICSEARCH_ALT_URL"])) if ENV["ELASTICSEARCH_ALT_URL"]
  end

  Elasticsearch::Model.client = $search[:main]

  $elasticsearch = {}.tap do |hash|
    hash[:pool] = ConnectionPool.new(size: ENV.fetch("DB_POOL", 1)) {
      client = HTTP
        .use(instrumentation: { instrumenter: ActiveSupport::Notifications.instrumenter, namespace: "search" })
        .persistent(ENV["ELASTICSEARCH_NEXT_URL"])
      if ENV["ELASTICSEARCH_NEXT_USERNAME"] && ENV["ELASTICSEARCH_NEXT_PASSWORD"]
        client = client.basic_auth(user: ENV["ELASTICSEARCH_NEXT_USERNAME"], pass: ENV["ELASTICSEARCH_NEXT_PASSWORD"])
      end
      client
    } if ENV["ELASTICSEARCH_NEXT_URL"]
  end

  if Rails.env.development? || Rails.env.test?
    Elasticsearch::Model.client.transport.tracer = ActiveSupport::Logger.new("log/elasticsearch.log")
    begin
      Entry.__elasticsearch__.create_index!
      Search::Client.request(:put, Entry.table_name, json: entries_mapping)
      Search::Client.request(:put, Action.table_name, json: actions_mapping)
    rescue
      nil
    end
  end
end

ActiveSupport::Notifications.subscribe("start_request.search") do |name, start, finish, id, payload|
  if Rails.env.development?
    Rails.logger.info(search: "request", payload: payload.dig(:request)&.body&.source)
  end
end

ActiveSupport::Notifications.subscribe("request.search") do |name, start, finish, id, payload|
  if Rails.env.development?
    Rails.logger.info(search: "response", payload: payload.dig(:response)&.parse)
  end
end
