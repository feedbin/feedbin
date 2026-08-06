class SavedSearch < ApplicationRecord
  belongs_to :user

  # saved_searches.name is NOT NULL, and without this the violation surfaces
  # below the validation layer as a 500 the controller cannot report.
  validates :name, presence: true

  # The same check Action runs. An unclosed quote is the commonest way to
  # mistype a search, and a stored one returns nothing forever with no error
  # anywhere the user can see.
  validate :query_valid

  def first_letter
    letter = "default"
    if name.present?
      letter = name[0].downcase
    end
    letter
  end

  def sourceable
    Sourceable.new(
      type: self.class.name,
      id: id,
      title: name
    )
  end

  private

  def query_valid
    return if query.blank? || user.blank?
    built = Entry.build_query(user: user, query: query)
    result = Search.client { _1.validate(Search.index_name(Entry.table_name), query: {query: built[:query]}) }
    errors.add :query, "syntax is invalid" if result == false
  end
end
