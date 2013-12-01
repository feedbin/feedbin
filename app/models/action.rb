class Action < ActiveRecord::Base
    belongs_to :user

    validate :validate_query

    after_commit :search_percolate_store, on: [:create, :update]
    after_destroy :search_percolate_remove

    def search_percolate_store
      action_feed_ids = self.feed_ids
      action_query = self.query
      result = Entry.index.register_percolator_query(self.id) do |search|
        search.filtered do
          unless action_query.blank?
            query { string Entry.escape_search(action_query) }
          end
          filter :terms, feed_id: action_feed_ids.map(&:to_i)
        end
      end
      if result.nil?
        Honeybadger.notify(
          error_class: "Action Percolate Save",
          error_message: "Action Percolate Save Failure",
          parameters: {id: self.id}
        )
      end
    end

    def search_percolate_remove
      Entry.index.unregister_percolator_query(self.id)
    end

    def validate_query
      # errors.add(:query, 'is invalid')
    end

end
