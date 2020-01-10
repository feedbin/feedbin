class AuthenticationToken < ApplicationRecord
  belongs_to :user

  enum purpose: {cookies: 0, feeds: 1, newsletters: 2, pages: 2}
end
