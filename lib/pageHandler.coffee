_ = require 'underscore'

util = require './util'
state = require './state'
revision = require './revision'
addToJournal = require './addToJournal'
newPage = require('./page').newPage

module.exports = pageHandler = {}

pageHandler.useLocalStorage = ->
  $(".login").length > 0

pageFromLocalStorage = (slug)->
  if json = localStorage[slug]
    JSON.parse(json)
  else
    undefined

recursiveGet = ({pageInformation, whenGotten, whenNotGotten, localContext}) ->
  {slug,rev,site} = pageInformation

  if site
    localContext = []
  else
    site = localContext.shift()

  site = 'origin' if site is window.location.host
  site = null if site=='view'

  if site?
    if site == 'local'
      if localPage = pageFromLocalStorage(pageInformation.slug)
        #NEWPAGE local from pageHandler.get 
        return whenGotten newPage(localPage, 'local' )
      else
        return whenNotGotten()
    else
      if site == 'origin'
        url = "/#{slug}.json"
      else
        url = "http://#{site}/#{slug}.json"
  else
    url = "/#{slug}.json"

  $.ajax
    type: 'GET'
    dataType: 'json'
    url: url + "?random=#{util.randomBytes(4)}"
    success: (page) ->
      page = revision.create rev, page if rev
      #NEWPAGE server from pageHandler.get
      return whenGotten newPage(page, site)
    error: (xhr, type, msg) ->
      if (xhr.status != 404) and (xhr.status != 0)
        console.log 'pageHandler.get error', xhr, xhr.status, type, msg
        #NEWPAGE trouble from PageHandler.get
        troublePageObject = newPage {title: "Trouble: Can't Get Page"}, null
        troublePageObject.addParagraph """
The page handler has run into problems with this   request.
<pre class=error>#{JSON.stringify pageInformation}</pre>
The requested url.
<pre class=error>#{url}</pre>
The server reported status.
<pre class=error>#{xhr.status}</pre>
The error type.
<pre class=error>#{type}</pre>
The error message.
<pre class=error>#{msg}</pre>
These problems are rarely solved by reporting issues.
There could be additional information reported in the browser's console.log.
More information might be accessible by fetching the page outside of wiki.
<a href="#{url}" target="_blank">try-now</a>
"""
        return whenGotten troublePageObject
      if localContext.length > 0
        recursiveGet( {pageInformation, whenGotten, whenNotGotten, localContext} )
      else
        whenNotGotten()

pageHandler.get = ({whenGotten,whenNotGotten,pageInformation}  ) ->

  unless pageInformation.site
    if localPage = pageFromLocalStorage(pageInformation.slug)
      localPage = revision.create pageInformation.rev, localPage if pageInformation.rev
      return whenGotten newPage( localPage, 'local' )

  pageHandler.context = ['view'] unless pageHandler.context.length

  recursiveGet
    pageInformation: pageInformation
    whenGotten: whenGotten
    whenNotGotten: whenNotGotten
    localContext: _.clone(pageHandler.context)


pageHandler.context = []

pushToLocal = ($page, pagePutInfo, action) ->
  if action.type == 'create'
    page = {title: action.item.title, story:[], journal:[]}
  else
    page = pageFromLocalStorage pagePutInfo.slug
    page ||= $page.data("data")
    page.journal = [] unless page.journal?
    if (site=action['fork'])?
      page.journal = page.journal.concat({'type':'fork','site':site})
      delete action['fork']
    page.story = $($page).find(".item").map(-> $(@).data("item")).get()
  page.journal = page.journal.concat(action)
  localStorage[pagePutInfo.slug] = JSON.stringify(page)
  addToJournal $page.find('.journal'), action

pushToServer = ($page, pagePutInfo, action) ->
  $.ajax
    type: 'PUT'
    url: "/page/#{pagePutInfo.slug}/action"
    data:
      'action': JSON.stringify(action)
    success: () ->
      addToJournal $page.find('.journal'), action
      if action.type == 'fork' # push
        localStorage.removeItem $page.attr('id')
    error: (xhr, type, msg) ->
      console.log "pageHandler.put ajax error callback", type, msg

pageHandler.put = ($page, action) ->

  checkedSite = () ->
    switch site = $page.data('site')
      when 'origin', 'local', 'view' then null
      when location.host then null
      else site

  # about the page we have
  pagePutInfo = {
    slug: $page.attr('id').split('_rev')[0]
    rev: $page.attr('id').split('_rev')[1]
    site: checkedSite()
    local: $page.hasClass('local')
  }
  forkFrom = pagePutInfo.site
  console.log 'pageHandler.put', action, pagePutInfo

  # detect when fork to local storage
  if pageHandler.useLocalStorage()
    if pagePutInfo.site?
      console.log 'remote => local'
    else if !pagePutInfo.local
      console.log 'origin => local'
      action.site = forkFrom = location.host
    # else if !pageFromLocalStorage(pagePutInfo.slug)
    #   console.log ''
    #   action.site = forkFrom = pagePutInfo.site
    #   console.log 'local storage first time', action, 'forkFrom', forkFrom

  # tweek action before saving
  action.date = (new Date()).getTime()
  delete action.site if action.site == 'origin'

  # update dom when forking
  if forkFrom
    # pull remote site closer to us
    $page.find('h1 img').attr('src', '/favicon.png')
    $page.find('h1 a').attr('href', '/')
    $page.data('site', null)
    $page.removeClass('remote')
    #STATE -- update url when site changes
    state.setUrl()
    if action.type != 'fork'
      # bundle implicit fork with next action
      action.fork = forkFrom
      addToJournal $page.find('.journal'),
        type: 'fork'
        site: forkFrom
        date: action.date

  # store as appropriate
  if pageHandler.useLocalStorage() or pagePutInfo.site == 'local'
    pushToLocal($page, pagePutInfo, action)
    $page.addClass("local")
  else
    pushToServer($page, pagePutInfo, action)

