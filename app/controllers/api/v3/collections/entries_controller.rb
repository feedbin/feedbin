module Api
  module V3
    module Collections
      # A collection's entries with their membership, and the writes to one
      # membership: add (Recently Read, Recently Played, Airshow), and
      # Airshow's update and remove. Unread, Starred and Updated are written
      # with the state verbs instead.
      class EntriesController < ApiController
        include CollectionScoped
        include SearchPage

        before_action -> { ensure_collection_accepts("add") }, only: :create
        before_action -> { ensure_collection_accepts("update") }, only: :update
        before_action -> { ensure_collection_accepts("remove") }, only: :destroy

        def index
          return render_search_page(EntrySearch.new(@user, query: @collection.query)) if @collection.search?

          limit = page_limit
          page = @collection.page(limit: limit, cursor: cursor_fields)
          entries, memberships = @collection.entries_on(page)
          render_list(
            serialize_entries(entries, memberships: memberships),
            page: page_object(limit: limit, next_cursor: page.next_cursor, more: page.more?),
            meta: {as_of: as_of}
          )
        end

        def create
          render json: @collection.add(body)
        end

        def update
          render json: @collection.update_entry(params[:id], body)
        end

        def destroy
          @collection.remove(params[:id])
          head :no_content
        end
      end
    end
  end
end
