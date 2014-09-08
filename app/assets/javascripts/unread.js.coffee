window.feedbin ?= {}

class UnreadCounts
  constructor: (data) ->
    @data ?= data
    @tagMap = @buildTagMap(@data.tag_map)
    @unreadEntries = @sortUnread(data.unread_entries)
    counts = @organizeCounts()
    @byFeed = counts.byFeed
    @byTag = counts.byTag
    @unread = counts.unread

  organizeCounts: () ->
    counts =
      byFeed: {}
      byTag: {}
      unread: []

    for unreadEntry in @unreadEntries
      feedId = @feedId(unreadEntry)
      entryId = @entryId(unreadEntry)

      counts.unread.push(entryId)

      counts.byFeed[feedId] = counts.byFeed[feedId] || []
      counts.byFeed[feedId].push(entryId)

      if (feedId of @tagMap)
        tags = @tagMap[feedId]
        for tagId in tags
          counts.byTag[tagId] = counts.byTag[tagId] || []
          counts.byTag[tagId].push(entryId)

    counts

  sortUnread: (unreadEntries) ->
    if @data.entry_sort == 'ASC'
      unreadEntries.sort (a, b) =>
        @published(a) - @published(b)
    else
      unreadEntries.sort (a, b) =>
        @published(b) - @published(a)
    unreadEntries

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

    feedbin.applyCounts()

  markEntryUnread: (entryId, feedId, published) ->
    unreadEntry = [feedId, entryId, published]
    console.log
    @unreadEntries.push(unreadEntry)
    @unreadEntries = @sortUnread(@unreadEntries)
    counts = @organizeCounts()
    @byFeed = counts.byFeed
    @byTag = counts.byTag
    @unread = counts.unread
    feedbin.applyCounts()

  buildTagMap: (tagArray) ->
    object = {}
    object[item[0]] = item[1] for item in tagArray
    object

  feedId: (unreadEntry) ->
    unreadEntry[0]

  entryId: (unreadEntry) ->
    unreadEntry[1]

  published: (unreadEntry) ->
    unreadEntry[2]

class Unread
  instance = null
  @get: (data) ->
    instance ?= new UnreadCounts(data)

feedbin.Unread = Unread