# Preview all emails at http://localhost:3000/rails/mailers/entry_mailer
class EntryMailerPreview < ActionMailer::Preview
  def mailer
    EntryMailer.mailer(Entry.first.id, "example@example.com", Entry.first.title, nil, "example@example.com", "Your Name", false)
  end
end
