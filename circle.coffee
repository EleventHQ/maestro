Request      = require 'request'
TokenService = require './tokenable.js'
YAML         = require 'yamljs'

class CircleCI
  constructor: (@project)->
    @org = YAML.load('./config/github.yml').repo.org
    @api = "https://circleci.com/api/v1/project/#{@org}/#{@project}"

  execute: ->
    @followProject().
      then(@configureEnvironmentVariables).
      then(@configureSlackNotifications).
      then(@andTestSlackHook)

  # TODO: May have to send project-id
  andTestSlackHook: => @request 'post', '/hooks/slack/test'

  configureEnvironmentVariables: -> # TODO

  configureSlackNotifications: =>
    new TokenService('slack').then (token)=>
      @request 'put', '/settings', slack_webhook_url: "https://#{token}"

  followProject: => @request 'post', '/follow'

  request: (method, path, data)=>
    new TokenService('circle').then (token)=>
      console.log @url(path, token)
      Request[method].call @, @url(path, token), form: data, (error, response, body)=>
        console.log error
        console.log response
        console.log body

  url: (path, token)=> @api + path + '?circle-token=' + token

module.exports = CircleCI

