@KDApps = {}

class KodingAppsController extends KDController

  deafultManifest = (type)->
    {profile} = KD.whoami()
    version       : "0.1"
    name          : "#{type.capitalize()} Application"
    path          : "~/Applications/#{type.capitalize()}.kdapp"
    homepage      : "#{profile.nickname}.koding.com/#{type}"
    author        : "#{profile.firstName} #{profile.lastName}"
    repository    : "git://github.com/#{profile.nickname}/#{type.capitalize()}.kdapp.git"
    description   : "a #{type} Koding application template."
    source        :
      blocks      :
        app       :
          files   : [ "./index.coffee" ]
      stylesheets : [ "./resources/style.css" ]
    options       :
      type        : "tab"
    icns          :
      "64"        : "./resources/icon.64.png"
      "128"       : "./resources/icon.128.png"
      "160"       : "./resources/icon.160.png"
      "256"       : "./resources/icon.256.png"
      "512"       : "./resources/icon.512.png"

  @manifests = {}

  # #
  # HELPERS
  # #

  getAppPath = (app)->

    {profile} = KD.whoami()
    path = if /^~/.test app.path then "/Users/#{profile.nickname}#{app.path.substr(1)}"
    else app.path

    path += "/" unless path[path.length-1] is "/"

    return path

  getManifestFromPath = (path, callback = noop)->

    folderName = (arr = path.split("/"))[arr.length-1]
    app        = null

    for own name, manifest of KodingAppsController.manifests
      do ->
        app = manifest if manifest.path.search(folderName) > -1

    return app

  # #
  # FETCHERS
  # #

  fetchApps:(callback)->

    if Object.keys(@constructor.manifests).length isnt 0
      callback null, @constructor.manifests
    else
      @fetchAppsFromDb (err, apps)=>
        if err
          @fetchAppsFromFs (err, apps)=>
            if err then callback()
            else
              callback null, apps
        else
          callback? err, apps

  fetchAppsFromFs:(callback)->

    path = "/Users/#{KD.whoami().profile.nickname}/Applications"

    @getSingleton("kiteController").run
      withArgs  :
        command : "ls #{path} -lpva"
    , (err, response)=>
      if err
        warn err
        callback err
      else
        files = FSHelper.parseLsOutput [path], response
        apps  = []
        stack = []

        files.forEach (file)->
          if /\.kdapp$/.test file.name
            apps.push file

        apps.forEach (app)->
          manifest = if app.type is "folder" then FSHelper.createFileFromPath "#{app.path}/.manifest" else app
          stack.push (cb)->
            manifest.fetchContents cb

        manifests = @constructor.manifests
        async.parallel stack, (err, results)->
          if err
            warn err
            callback? err
          else
            results.forEach (app)->
              app = JSON.parse app
              manifests["#{app.name}"] = app
            callback? err, manifests

  fetchAppsFromDb:(callback)->

    appManager.fetchStorage "KodingApps", "1.0", (err, storage)=>
      if err
        warn err
        callback err
      else
        apps = storage.getAt "bucket.apps"
        if apps and Object.keys(apps).length > 0
          @constructor.manifests = apps
          callback null, apps
        else
          callback new Error "There are no apps in the app storage."

  fetchCompiledApp:(name, callback)->

    @getSingleton("kiteController").run
      withArgs  :
        command : "cat /Users/#{KD.whoami().profile.nickname}/Applications/#{name}.kdapp/index.js"
    , (err, response)=>
      if err then warn err
      callback err, response


  # #
  # MISC
  # #

  refreshApps:(callback)->

    @constructor.manifests = {}
    KDApps = {}
    @fetchAppsFromFs callback

  putAppsToAppStorage:(apps)->

    appManager.fetchStorage "KodingApps", "1.0", (err, storage)->
      storage.update {
        $set: { "bucket.apps" : apps }
      }, => log arguments,"kodingAppsController storage updated"

  defineApp:(name, script)->

    KDApps[name] = script

  getApp:(name, callback = noop)->

    if KDApps[name]
      callback KDApps[name]
    else
      @fetchCompiledApp name, (err, script)=>
        if err
          @compileSource name, (err)=>
            if err
              new KDNotificationView type : "mini", title : "There was an error, please try again later!"
              callback err
            else
              callback KDApps[name]
        else
          @defineApp name, script
          callback KDApps[name]

  # #
  # KITE INTERACTIONS
  # #
  runApp:(name, callback)->

    log "app to run:", name
    callback?()

  addScript:(app, scriptInput, callback)->

    if /^\.\//.test scriptInput
      @getSingleton("kiteController").run
        withArgs  :
          command : "cat #{getAppPath app}/#{scriptInput}"
      , (err, response)=>
        if err then warn err

        if /.coffee$/.test scriptInput
          require ["coffee-script"], (coffee)->
            js = coffee.compile response, { bare : yes }
            callback err, js
        else
          callback err, response
    else
      callback null, scriptInput


  saveCompiledApp:(app, script, callback)->

    @getSingleton("kiteController").run
      toDo        : "uploadFile"
      withArgs    : {
        path      : FSHelper.escapeFilePath "#{getAppPath app}index.js"
        contents  : script
      }
    , (err, response)=>
      if err then warn err
      log response, "App saved!"
      callback?()

  publishApp:(path, callback)->

    kiteController = @getSingleton('kiteController')
    appName        = getManifestFromPath(path).name

    @getApp appName, (appScript)=>

      manifest    = @constructor.manifests[appName]
      {nickname}  = KD.whoami().profile
      publishPath = FSHelper.escapeFilePath "/opt/Apps/#{nickname}/#{manifest.name}/#{manifest.version}"
      userAppPath = if /~\//.test manifest.path
        manifest.path.replace("~/", "/Users/#{nickname}/")
      else
        "#{manifest.path}/"
      options     =
        toDo          : "publishApp"
        withArgs      :
          version     : manifest.version
          appName     : manifest.name
          userAppPath : userAppPath

      kiteController.run options, (err, res)=>
        log "app is being published"
        if err then warn err
        else
          jAppData =
            title       : manifest.name or "Application Title"
            body        : manifest.description or "Application description"
            manifest    : manifest
          appManager.tell "Apps", "createApp", jAppData, (err, app)=>
            log app, "app published"
            appManager.openApplication "Apps", yes, (instance)=>
              # instance.feedController.changeActiveSort "meta.modifiedAt"
              callback?()
  compileApp:(path, callback)->

    manifest = getManifestFromPath path

    @compileSource manifest.name, => callback?()

  compileSource:(name, callback)->

    kallback = (app)=>

      return warn "#{name}: No such app!" unless app

      {source} = app
      {blocks, stylesheets} = source
      {nickname} = KD.whoami().profile


      orderedBlocks = []
      for blockName, blockOptions of blocks
        blockOptions.name = blockName
        if blockOptions.order? and not isNaN(order = parseInt(blockOptions.order, 10))
          orderedBlocks[order] = blockOptions
        else
          orderedBlocks.push blockOptions

      blockStrings = []

      asyncStack   = []

      orderedBlocks.forEach (block)=>

        if block.pre
          asyncStack.push (cb)=> @addScript app, block.pre, cb

        if block.files
          {files} = block
          files.forEach (file, index)=>
            if "object" is typeof file
              for fileName, fileExtras of file
                do =>
                  # log fileExtras.pre  if fileExtras.pre
                  if fileExtras.pre
                    asyncStack.push (cb)=> @addScript app, fileExtras.pre, cb
                  # log fileName
                  asyncStack.push (cb)=> @addScript app, fileName, cb
                  # log fileExtras.post if fileExtras.post
                  if fileExtras.post
                    asyncStack.push (cb)=> @addScript app, fileExtras.post, cb
            else
              # log file
              asyncStack.push (cb)=> @addScript app, file, cb
        # log block.post if block.post
        if block.post
          asyncStack.push (cb)=> @addScript app, block.post, cb

      if stylesheets
        stylesheets.forEach (sheet)->
          if /(http)|(:\/\/)/.test sheet
            warn "external sheets cannot be used"
          else
            sheet = sheet.replace /(^\.\/)|(^\/+)/, ""
            $("head ##{__utils.slugify name}").remove()
            $('head').append("<link id='#{__utils.slugify name}' rel='stylesheet' href='#{KD.appsUri}/#{nickname}/#{__utils.stripTags name}/latest/#{__utils.stripTags sheet}'>")


      async.parallel asyncStack, (error, result)=>

        log "concatenating the app"

        _final = "(function() {\n\n/* KDAPP STARTS */"
        result.forEach (output)=>
          _final += "\n\n/* BLOCK STARTS */\n\n"
          _final += "#{output}"
          _final += "\n\n/* BLOCK ENDS */\n\n"
        _final += "/* KDAPP ENDS */\n\n}).call();"


        _final = @defineApp app.name, _final
        @saveCompiledApp app, _final, =>
          callback?()

    unless @constructor.manifests[name]
      @fetchApps (err, apps)=> kallback apps[name]
    else
      kallback @constructor.manifests[name]

  installApp:(app, callback)->

    @fetchApps (err, manifests = {})=>
      if err
        warn err
        new KDNotificationView type : "mini", title : "There was an error, please try again later!"
        callback? err
      else
        log manifests
        if app.title in Object.keys(manifests)
          new KDNotificationView type : "mini", title : "App is already installed!"
          callback? msg : "App is already installed!"
        else
          log "installing the app: #{app.title}"
          app.fetchCreator (err, acc)=>
            if err
              callback? err
            else
              kiteController = @getSingleton("kiteController")
              options        =
                toDo          : "installApp"
                withArgs      :
                  owner       : acc.profile.nickname
                  username    : KD.whoami().profile.nickname
                  appName     : app.manifest.name

              kiteController.run options, (err, res)=>
                if err then warn err
                else
                  appManager.openApplication "Develop"
                  callback?()
  newAppModal = null

  makeNewApp:(callback)->

    return callback?() if newAppModal

    newAppModal = new KDModalViewWithForms
      title                       : "Create a new Application"
      # content                   : "<div class='modalformline'>Please select the application type you want to start with.</div>"
      overlay                     : yes
      width                       : 500
      height                      : "auto"
      tabs                        :
        navigable                 : yes
        forms                     :
          form                    :
            buttons               :
              "Blank Application" :
                cssClass          : "modal-clean-gray"
                callback          : ->
                  newAppModal.destroy()
                  callback? yes
              "Sample Application":
                cssClass          : "modal-clean-gray"
                callback          : ->
                  newAppModal.destroy()
                  callback? yes
            fields                :
              name                :
                label             : "Application Name:"
                name              : "name"
                placeholder       : "name your application..."
                validate          :
                  rules           :
                    required      : yes
                  messages        :
                    required      : "application name is required!"

    newAppModal.once "KDObjectWillBeDestroyed", ->
      newAppModal = null
      callback? null

  forkRepoCommandMap = ->
    git : "git clone"
    svn : "svn checkout"
    hg  : "hg clone"

  cloneApp:(path, callback)->

    kiteController = @getSingleton('kiteController')

    @fetchApps (err, manifests = {})=>
      if err
        warn err
        new KDNotificationView type : "mini", title : "There was an error, please try again later!"
        callback? err
      else
        manifest = getManifestFromPath path
        # debugger
        log "cloning the app: #{manifest.name}"
        log "checking the repo: #{manifest.repo}"
        {repo} = manifest

        if /^git/.test repo      then repoType = "git"
        else if /^svn/.test repo then repoType = "svn"
        else if /^hg/.test repo  then repoType = "hg"
        else
          log repoType,">>>>"
          err = "Unsupported repository specified, quitting!"
          new KDNotificationView type : "mini", title : err
          callback? err
          return no

        appPath = "/Users/#{KD.whoami().profile.nickname}/Applications/#{manifest.name}.kdapp"
        kiteController.run
          withArgs    :
            command   : "mv #{appPath} #{appPath}.old#{@utils.getRandomNumber 9999}"
        , (err, response)->
          if err then warn err
          kiteController.run
            withArgs    :
              command   : "#{forkRepoCommandMap()[repoType]} #{repo} /Users/#{KD.whoami().profile.nickname}/Applications/#{manifest.name}.kdapp/"
          , (err, response)->
            if err then warn err
            else
              log response, "App cloned!"
            callback? err, response
