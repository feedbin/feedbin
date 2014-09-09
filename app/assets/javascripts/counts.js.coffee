window.feedbin ?= {}

class _Counts
  constructor: (data) ->
    @data ?= data
    @tagMap = @buildTagMap(@data.tag_map)
    @unreadEntries = @sort(data.unread_entries)
    counts = @organizeCounts(@unreadEntries)
    @byFeed = counts.byFeed
    @byTag = counts.byTag
    @unread = counts.all

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

  sort: (entries) ->
    if @data.entry_sort == 'ASC'
      entries.sort (a, b) =>
        @published(a) - @published(b)
    else
      entries.sort (a, b) =>
        @published(b) - @published(a)
    entries

  markEntryRead: (entryId, feedId) ->
    # total unread
    entryIndex = @unread.indexOf(entryId);
    if entryIndex > -1
      @unread.splice(entryIndex, 1);
      @unreadEntries.splice(entryIndex, 1);

    # feeds
    if (feedId of @byFeed)
      entryIndex = @byFeed[feedId].indexOf(entryId);
      if entryIndex > -1
        @byFeed[feedId].splice(entryIndex, 1);

    # tags
      if (feedId of @tagMap)
        tags = @tagMap[feedId]
        for tagId in tags
          entryIndex = @byTag[tagId].indexOf(entryId);
          if entryIndex > -1
            @byTag[tagId].splice(entryIndex, 1);

  markEntryUnread: (entryId, feedId, published) ->
    unreadEntry = @buildEntry
      feedId: feedId
      entryId: entryId
      published: published
    @unreadEntries.push(unreadEntry)
    @unreadEntries = @sort(@unreadEntries)
    counts = @organizeCounts(@unreadEntries)
    @byFeed = counts.byFeed
    @byTag = counts.byTag
    @unread = counts.all

  buildTagMap: (tagArray) ->
    object = {}
    object[item[0]] = item[1] for item in tagArray
    object

  feedId: (entry) ->
    entry[0]

  entryId: (entry) ->
    entry[1]

  published: (entry) ->
    entry[2]

  buildEntry: (params) ->
    [params.feedId, params.entryId, params.published]

class Counts
  instance = null
  @get: (data) ->
    instance ?= new _Counts(data)

feedbin.Counts = Counts