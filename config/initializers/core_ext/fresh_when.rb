module ActionController
  module ConditionalGet
    alias original_fresh_when fresh_when

    def fresh_when(*args)
      unless request.user_agent =~ /^Mr\. Reader 2\.1/ || request.user_agent =~ /^Unread/
        original_fresh_when(*args)
      end
    end
  end
end
