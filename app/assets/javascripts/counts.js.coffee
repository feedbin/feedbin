window.feedbin ?= {}

class _Counts
  constructor: (tagMap, sortOrder, unreadEntries, starredEntries) ->
    @tagMap = @buildTagMap(tagMap)
    @collections =
      unread: @sort(unreadEntries, sortOrder)
      starred: @sort(starredEntries, 'DESC')
    @counts =
      unread: @organizeCounts(@collections.unread)
      starred: @organizeCounts(@collections.starred)

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

  addEntry: (entryId, feedId, published, collection) ->
    entry = @buildEntry
      feedId: feedId
      entryId: entryId
      published: published
    @collections[collection].push(entry)
    @collections[collection] = @sort(@collections[collection])
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

  sort: (entries, sortOrder) ->
    if sortOrder == 'ASC'
      entries.sort (a, b) =>
        @published(a) - @published(b)
    else
      entries.sort (a, b) =>
        @published(b) - @published(a)
    entries

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
    [params.feedId, params.entryId, params.published]

  feedId: (entry) ->
    entry[0]

  entryId: (entry) ->
    entry[1]

  published: (entry) ->
    entry[2]

class Counts
  instance = null
  @get: (tagMap, sortOrder, unreadEntries, starredEntries) ->
    instance ?= new _Counts(tagMap, sortOrder, unreadEntries, starredEntries)

feedbin.Counts = Counts