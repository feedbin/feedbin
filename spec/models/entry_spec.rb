require 'rails_helper'

describe Entry do
  describe "#build_search" do
    context "with unread flag" do
      it "works" do
        result = described_class.build_search({ query: 'is:unread cheeseburgers' })
        expect(result[:read]).to eq false
        expect(result[:query]).to eq ' cheeseburgers'
      end
    end

    context "with read flag" do
      it "works" do
        result = described_class.build_search({ query: 'is:read bigmac' })
        expect(result[:read]).to eq true
        expect(result[:query]).to eq ' bigmac'
      end
    end

    context "with unstarred flag" do
      it "works" do
        result = described_class.build_search({ query: 'is:unstarred cheeseburgers' })
        expect(result[:starred]).to eq false
        expect(result[:query]).to eq ' cheeseburgers'
      end
    end

    context "with unstarred flag" do
      it "works" do
        result = described_class.build_search({ query: 'is:unstarred bigmac' })
        expect(result[:starred]).to eq false
        expect(result[:query]).to eq ' bigmac'
      end
    end
  end

  describe "#mark_as_unread"

  describe "#fully_qualified_url" do
    it "works" do
      feed = create(:feed)
      entry = Entry.new(url: 'http://tema.livejournal.com/feed.rss', feed: feed)
      expect(entry.fully_qualified_url).to eq entry.url
    end
  end
end
