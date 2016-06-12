# Labelize `/labelize repository-name`
# Synchronizes repository with canonical labels in:
#   config/github.labels.yml

AWS          = require 'aws-sdk'
GitHub       = require 'github'
Promise      = require 'promise'
TokenService = require './tokenable.js'
YAML         = require 'yamljs'

class Labelize
  constructor: (@request)->
    @config = YAML.load './config/github.yml'
    @github = new GitHub(@config.api)
    @labels = YAML.load './config/github.labels.yml'

  authenticate: (token)=>
    new Promise (fulfill, reject)=>
      @github.authenticate type: 'oauth', token: token
  
  createLabels: =>
    labels = []

    Object.keys(@labels).forEach (theme)=>
      @labels[theme].entries.forEach (label)=>
        labels.push new Promise (fulfill, reject)=>
          params =
            color: String(@labels[theme].color)
            name: label
            repo: @name()
            user: @config.repo.org

          @getLabels (existingLabels)=>
            if existingLabels.map((l)=> l.name).indexOf(label.name) > -1
              @github.issues.updateLabel(params, fulfill)
            else
              @github.issues.createLabel(params, fulfill)

    Promise.all(labels)

  deleteDefaultLabelsNotInOurList: =>
    new Promise (fulfill, reject)=>
      @getLabels (labels)=>
        operations = labels.filter(@notInOurConfiguration).map (label)=>
          new Promise (deleted, failed)=>
            params =
              user: @config.repo.org
              repo: @name()
              name: label.name

            @github.issues.deleteLabel(params, deleted)

        Promise.all(operations).then(fulfill, reject)

  execute: ->
    new TokenService('github').
      then(@authenticate).
      then(@deleteDefaultLabelsNotInOurList).
      then(@createLabels).
      then => new Promise (fulfill, reject)=>
        console.log "Applied labels to #{@name()}."
        fulfill()

  getLabels: (callback)=>
    return callback(@githubLabels) if @githubLabels

    params =
      user: @config.repo.org
      repo: @name()

    @github.issues.getLabels params, (err, labels)=>
      callback(@githubLabels = labels)

  name: -> @request.post['text']
  
  notInOurConfiguration: (label)=>
    inOurConfiguration = false
    Object.keys(@labels).forEach (theme)=>
      inOurConfiguration ||= @labels[theme].entries.indexOf(label.name) > -1
    inOurConfiguration

module.exports = Labelize

