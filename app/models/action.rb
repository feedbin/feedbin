class Action < ActiveRecord::Base
    belongs_to :user

    validate :validate_query

    private

    def validate_query
      # errors.add(:query, 'is invalid')
    end

end
