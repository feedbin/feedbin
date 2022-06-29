module ActionController
  module ConditionalGet
    alias original_fresh_when fresh_when

    def fresh_when(*args, **kwargs)
      unless request.user_agent =~ /^Unread/
        original_fresh_when(*args, **kwargs)
      end
    end
  end
end
