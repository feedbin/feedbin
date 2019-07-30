window.feedbin ?= {}

class _Counts
  constructor: (options) ->
    @setData(options)

  update: (options) ->
    @setData(options)

  flatten: (data) ->
    shouldFlatten = !!(data && data[0] && data[0][0] && data[0][0][0])
    if shouldFlatten
      [].concat.apply([], data)
    else
      data

  setData: (options) ->
    @tagMap = options.tag_map
    @savedSearches = options.saved_searches
    @collections =
      unread: @flatten(options.unread_entries)
      starred: @flatten(options.starred_entries)
      updated: @flatten(options.updated_entries)
    @counts = @allCounts()

  allCounts: ->
    {
      unread: @organizeCounts(@collections.unread)
      starred: @organizeCounts(@collections.starred)
      updated: @organizeCounts(@collections.updated)
    }


  removeEntry: (entryId, feedId, collection) ->
    index = @counts[collection].all.indexOf(entryId);
    if index > -1
      @counts[collection].all.splice(index, 1);
      @collections[collection].splice(index, 1);

    @removeFromCollection(collection, 'byFeed', entryId, feedId)

    if (feedId of @tagMap)
      tags = @tagMap[feedId]
      for tagId in tags
        @removeFromCollection(collection, 'byTag', entryId, tagId)

    if (@savedSearches)
      for searchID, entry_ids of @savedSearches
        @removeFromCollection(collection, 'bySavedSearch', entryId, searchID)

  addEntry: (entryId, feedId, collection) ->
    entry = @buildEntry
      feedId: feedId
      entryId: entryId
    @collections[collection].push(entry)
    @counts[collection] = @organizeCounts(@collections[collection])

  organizeCounts: (entries) ->
    counts =
      byFeed: {}
      byTag: {}
      bySavedSearch: {}
      all: []

    for entry in entries
      feedId = @feedId(entry)
      entryId = @entryId(entry)

      counts.all.push(entryId)
      counts.byFeed[feedId] = counts.byFeed[feedId] || []
      counts.byFeed[feedId].push(entryId)

      if (feedId of @tagMap)
        tags = @tagMap[feedId]
        for tagId in tags
          counts.byTag[tagId] = counts.byTag[tagId] || []
          counts.byTag[tagId].push(entryId)

      if (@savedSearches)
        for searchID, entry_ids of @savedSearches
          if _.contains(entry_ids, entryId)
            counts.bySavedSearch[searchID] = counts.bySavedSearch[searchID] || []
            counts.bySavedSearch[searchID].push(entryId)

    counts

  removeFromCollection: (collection, group, entryId, groupId) ->
    items = @counts[collection][group][groupId]
    if typeof(items) != "undefined"
      index = items.indexOf(entryId);
      if index > -1
        @counts[collection][group][groupId].splice(index, 1);
      index

  buildEntry: (params) ->
    [params.feedId, params.entryId]

  feedId: (entry) ->
    entry[0]

  entryId: (entry) ->
    entry[1]

  isRead: (entryId) ->
    !_.contains(@counts.unread.all, entryId)

  isUpdated: (entryId) ->
    _.contains(@counts.updated.all, entryId)

  isStarred: (entryId) ->
    _.contains(@counts.starred.all, entryId)

  entriesInFeed: (feedId) ->
    result = @counts["unread"]["byFeed"][feedId]
    if typeof(result) == "undefined"
      0
    else
      result.length

  updateTagMap: (feedId, tagId) ->
    if tagId?
      @tagMap[feedId] = [tagId]
    else
      delete @tagMap[feedId]
    @counts = @allCounts()

class Counts
  instance = null
  @get: (tagMap, sortOrder, unreadEntries, starredEntries) ->
    instance ?= new _Counts(tagMap, sortOrder, unreadEntries, starredEntries)

feedbin.Counts = Counts