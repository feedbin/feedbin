class SavedSearch < ApplicationRecord
  belongs_to :user

  def first_letter
    letter = "default"
    if name.present?
      letter = name[0].downcase
    end
    letter
  end

end
