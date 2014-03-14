Controllers = angular.module 'iodocs.controllers', ['xml']

Controllers.controller 'SidebarCtrl', ->

Controllers.controller 'AuthCtrl', ($scope, $http) ->
  $scope.$watch ((s) -> "#{s.auth.token}#{s.apiInfo.baseURL}"), ->
    unless $scope.auth.token
      return $scope.auth.username = null

    {protocol, baseURL, publicPath} = $scope.apiInfo
    return unless baseURL
    url = "#{ protocol }://#{ baseURL }#{ publicPath }/user"
    req = $http.get(url, params: {token: $scope.auth.token})
    req.then ({data}) -> $scope.auth.username = data.user.username
    req.error -> $scope.auth.username = null

Controllers.controller 'ParameterInputCtrl', ($scope, $q, $timeout, getSuggestions, parameterHistoryKey, Storage) ->

    getStorageKey = ->
      pidx = $scope.params.indexOf $scope.parameter
      parameterHistoryKey $scope, $scope.parameter.Name, pidx

    storeHistory = (hist) -> Storage.put getStorageKey(), JSON.stringify(hist)

    getHistory = ->
      hist = Storage.get getStorageKey()
      if hist?
        try
          JSON.parse hist
        catch e
          []
      else
        []

    $scope.getSuggestions = ->
      if $scope.parameter.Options
        return getSuggestions $scope.params, $scope.parameter
      else
        d = $q.defer()
        d.resolve getHistory()
        return d.promise

Controllers.controller 'EndpointList', ->

arrayRegexp = /\[\]$/
bracesRexexp = /^{.*}$/

Controllers.controller 'ParameterCtrl', ($scope, getDefaultValue) ->
  p = $scope.parameter
  p.currentValue ?= p.Default unless p.changed
  p.currentName = p.Name

  $scope.repeatable = arrayRegexp.test p.Type
  $scope.removable = $scope.repeatable and (sib for sib in $scope.params when sib.Name is p.Name).length > 1
  $scope.type = p.Type?.replace(arrayRegexp, '')
  p.required = p.Required is 'Y'
  p.active ?= p.required
  $scope.switchable = not $scope.parameter.active
  $scope.variableName = /\?/.test p.Name

  $scope.change = ->
    p.active = true
    p.changed = true

  $scope.removeParam = ->
    i = $scope.params.indexOf p
    $scope.params.splice(i, 1)
  $scope.addParam = ->
    newParam = angular.copy(p)
    delete newParam.active
    i = $scope.params.indexOf p
    $scope.params.splice(i + 1, 0, newParam)

  $scope.$watch 'auth.token', (t) ->
    if p.currentValue is p.Default
      getDefaultValue($scope.params, p).then (v) -> p.currentValue = v

updateLocation = (loc, scope) ->
  httpMethod = scope.currentMethod.HTTPMethod
  uri = scope.currentMethod.URI
  newLoc = "/#{ scope.endpoint.identifier }/#{ httpMethod }#{ uri }"
  loc.replace().path newLoc

getCurrentValue = (ps, name) -> return p.currentValue for p in ps when p.Name is name

Controllers.controller 'MethodCtrl', ($scope, $http, getRepetitions, Defaults, ParamUtils, Storage, parameterHistoryKey, Markdown) ->
  $scope.params = angular.copy($scope.m.parameters)
  $scope.m.show ?= 'desc'

  $scope.description = $scope.m.Description
  if 'markdown' is $scope.m.DescriptionFormat
    $scope.htmlDesc = true
    $scope.description = Markdown.parse($scope.description)

  nRegex = /\{N\}/

  allDeps = {}
  for p in $scope.m.parameters when p.Repeat
    allDeps[name] = 1 for name in ParamUtils.getDependencies(p.Repeat)

  for name, _ of allDeps then do (name) ->
    $scope.$watch ((s) -> getCurrentValue s.params, name), (nv, ov) ->
      return if nv is ov
      oldParams = $scope.params
      $scope.params = angular.copy($scope.m.parameters)
      for pp in $scope.params
        oldValue = getCurrentValue oldParams, pp.Name
        pp.currentValue = oldValue if oldValue?
      expandNumberedParams $scope.params

  expandNumberedParams = (parameters) ->
    parameters.filter((p) -> p.Repeat).forEach (repeatedP) ->

      getRepetitions(parameters, repeatedP).then (things) ->
        i = parameters.indexOf repeatedP # Might have changed, need to get it late.
        defaultParser = new Defaults.DefaultParser repeatedP.Default
        parameters.splice(i, 1) # Remove the template
        for thing, thingIdx in things
          newP = angular.copy(repeatedP)
          newName = newP.Name.replace(nRegex, String(thingIdx + 1))
          newP.Name = p.currentName = newName
          newP.currentValue = defaultParser.parse thing
          newP.changed = newP.active = true
          parameters.splice(i++, 0, newP) # Insert newP where old P was, advancing the cursor.
    
  expandNumberedParams $scope.params

  saveParamValueToHistory = (p) ->
    return unless p.currentValue?
    key = parameterHistoryKey $scope, p.Name
    storedHist = Storage.get key
    hist = if storedHist? then JSON.parse(storedHist) else []
    toStore = String p.currentValue
    if toStore not in hist
      hist.push toStore
      Storage.put key, JSON.stringify(hist)

  $scope.run = ->
    m = $scope.m

    query =
      apiKey: $scope.auth.token
      httpMethod: m.HTTPMethod
      methodUri: m.URI
      params: {}

    for p, i in $scope.params when p.active
      console.log p
      query.params[p.currentName] = p.currentValue
      saveParamValueToHistory p

    if m.content
      query.body =
        Format: m.bodyContentType
        Content: m.content

    console.log(query)

    $http.post('run', query).then ({data}) ->
      data.query = query
      m.results.push data
      m.show = 'res'

Controllers.controller 'EndpointDetails', ($scope, $routeParams, $http, $location, Storage) ->

  $scope.currentEndpoint = $routeParams.endpointName
  httpMethod = $routeParams.method
  path = '/' + $routeParams.servicePath

  $scope.endpoint = e for e in $scope.endpoints when e.identifier is $scope.currentEndpoint

  return unless $scope.endpoint

  if httpMethod? and path?
    $scope.currentMethod = m for m in $scope.endpoint.methods when m.URI is path and m.HTTPMethod is httpMethod
  else
    $scope.currentMethod = $scope.endpoint.methods[0]

  m.active = false for m in $scope.endpoint.methods
  cm = $scope.currentMethod

  cm.active = true
  cm.results ?= []
  body = cm.body?[0]
  cm.bodyContentType = body?.contentType
  cm.content = body?.example

  console.log $scope.currentMethod

  updateLocation $location, $scope
  $scope.methodChanged = ->
    [cm] = (m for m in $scope.endpoint.methods when m.active)
    return unless cm?
    $scope.currentMethod = cm

  $scope.$watch ((s) -> s.currentMethod.HTTPMethod + s.currentMethod.URI), (nv, ov) ->
    updateLocation($location, $scope) if ov


c = 0

parseNode = (k, v) ->
  node = label: k, id: c++, children: []
  if Array.isArray v
    node.label += " [#{ v.length }]"
    for e, i in v
      node.children.push(parseNode(i, e))
  else if angular.isObject(v)
    node.label += " {#{ typeof v }}"
    for kk, vv of v
      node.children.push(parseNode(kk, vv))
  else
    node.label = "#{ k }: #{ JSON.stringify(v) }"
  return node

parseDOMElem = (elem) ->
  node =
    label: (elem.tagName or 'CONTENT')
    id: c++
    children: []
  if elem.attributes?
    for ai in [0 ... elem.attributes.length]
      attr = elem.attributes[ai]
      node.children.push label: """#{ attr.name } = "#{ attr.value }" """, id: c++, children: []
  if elem.childNodes?
    for ci in [0 ... elem.childNodes.length]
      node.children.push(parseDOMElem(elem.childNodes[ci]))
  if elem.nodeValue?
    node.children.push label: elem.nodeValue.replace(/(^\s+|\s+$)/g, ''), id: c++, children: []
  # Prune useless children
  node.children = (c for c in node.children when c.label and not (c.label is 'CONTENT' and c.children.length is 0))
  return node

expandTree = (tree, setting) ->
  for node in tree
    node.collapsed = setting
    expandTree node.children, setting

Controllers.controller 'ResponseCtrl', ($scope, xmlParser) ->

  $scope.navType = 'pills'
  $scope.showheaders = false
  $scope.params = $scope.res.query.params
  $scope.headers = $scope.res.headers
  $scope.hasParams = -> Object.keys($scope.params).length > 0
  $scope.parsedData = []
  $scope.tree = expanded: false

  ct = $scope.headers['content-type']
  if $scope.res.response?.length
    if ct.match(/^application\/json/)
      parsed = JSON.parse($scope.res.response)
      for k, v of parsed
        $scope.parsedData.push(parseNode(k, v))
    else if /^text\/xml/.test(ct) or /^application\/xml/.test(ct)
      dom = xmlParser.parse($scope.res.response)
      $scope.parsedData.push(parseDOMElem(dom.documentElement))

  $scope.isHTML = -> !!ct?.match /^text\/html/

  if ct.match(/separated/)
    patt = if ct.match(/comma/) then /,/ else /\t/
    $scope.flatFile = {headers: [], rows: []}
    lines = $scope.res.response.split('\n')
    # Some *very* custom code for dealing with results that have column headers.
    if $scope.params['columnheaders'] and $scope.params['columnheaders'] isnt 'none'
      [header, rows...] = lines
    else
      rows = lines
    $scope.flatFile.headers = header.split(patt) if header?
    for row in rows
      $scope.flatFile.rows.push(row.split(patt))

  $scope.$watch 'tree.expanded', (nv) -> expandTree $scope.parsedData, !nv