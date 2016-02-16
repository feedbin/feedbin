window.feedbin ?= {}

class _Counts
  constructor: (options) ->
    @setData(options)

  update: (options) ->
    @setData(options)

  setData: (options) ->
    @tagMap = @buildTagMap(options.tag_map)
    @collections =
      unread: options.unread_entries
      starred: options.starred_entries
      updated: options.updated_entries
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

    counts

  removeFromCollection: (collection, group, entryId, groupId) ->
    index = @counts[collection][group][groupId].indexOf(entryId);
    if index > -1
      @counts[collection][group][groupId].splice(index, 1);
    index

  buildTagMap: (tagArray) ->
    object = {}
    object[item[0]] = item[1] for item in tagArray
    object

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