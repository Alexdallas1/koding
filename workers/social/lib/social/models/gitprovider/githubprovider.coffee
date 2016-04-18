{ argv }    = require 'optimist'
GithubAPI   = require 'github'
KONFIG      = require('koding-config-manager').load("main.#{argv.c}")
Constants   = require './constants'
helpers     = require './utils/helpers'
async       = require 'async'
KodingError = require '../../error'

module.exports = GitHubProvider =

  importStackTemplate: (user, path, callback) ->

    [ empty, username, repo, tree, branch, rest... ] = path.split '/'
    return callback(new KodingError 'Invalid url')  if rest.length > 0

    oauth = user.getAt 'foreignAuth.github'

    if oauth
      GitHubProvider.importStackTemplateWithOauth oauth, username, repo, branch, callback
    else
      GitHubProvider.importStackTemplateWithRawUrl username, repo, branch, callback


  importStackTemplateWithOauth: (oauth, user, repo, branch, callback) ->

    { token } = oauth
    { debug, timeout, userAgent } = KONFIG.githubapi

    gh = new GithubAPI {
      version : '3.0.0'
      headers : { 'user-agent': userAgent }
      debug, timeout
    }

    gh.authenticate { type: 'oauth', token }

    { repos } = gh
    branch   ?= 'master'
    { TEMPLATE_PATH, README_PATH } = Constants
    queue = [
      (next) ->
        options = { user, repo, path: TEMPLATE_PATH, ref: branch }
        repos.getContent options, (err, data) ->
          return next err  if err
          next null, helpers.decodeContent data
      (next) ->
        options = { user, repo, path: README_PATH, ref: branch }
        repos.getContent options, (err, data) ->
          return next()  if err
          next null, helpers.decodeContent data
    ]

    return async.series queue, (err, results) ->
      return callback err  if err
      [ rawContent, description ] = results
      callback null, { rawContent, description, user, repo, branch }


  importStackTemplateWithRawUrl: (user, repo, branch, callback) ->

    { RAW_GITHUB_HOST, TEMPLATE_PATH, README_PATH } = Constants
    branch ?= 'master'

    queue = [
      (next) ->
        options =
          host   : RAW_GITHUB_HOST
          path   : "/#{user}/#{repo}/#{branch}/#{TEMPLATE_PATH}"
          method : 'GET'
        helpers.loadRawContent options, next
      (next) ->
        options =
          host   : RAW_GITHUB_HOST
          path   : "/#{user}/#{repo}/#{branch}/#{README_PATH}"
          method : 'GET'
        helpers.loadRawContent options, (err, readme) ->
          next null, readme
      ]

    return async.series queue, (err, results) ->
      return callback err  if err
      [ rawContent, description ] = results
      callback null, { rawContent, description, user, repo, branch }
