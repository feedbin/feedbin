module Elasticsearch
  module Model
    module Adapter
      module ActiveRecord
        module Records
          def records
            sql_records = klass.where(klass.primary_key => ids)
            sql_records = sql_records.includes(options[:includes]) if options[:includes]
            sql_records.instance_exec(response.response["hits"]["hits"]) do |hits|
              define_singleton_method :records do
                if defined?(::ActiveRecord) && ::ActiveRecord::VERSION::MAJOR >= 4
                  load
                else
                  __send__(:exec_queries)
                end
                @records.sort_by { |record| hits.index { |hit| hit["_id"].to_s == record.id.to_s } }
              end
            end
            sql_records
          end
        end
      end
    end
  end
end
