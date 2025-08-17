json.token @token
json.verified_token @verified_token
json.numbers @numbers
json.email "#{@token}@#{ENV["NEWSLETTER_ADDRESS_HOST"]}"

json.addresses @addresses do |address|
  json.email address.title
  json.description address.description
end

json.tags @user.tag_group.map(&:name)