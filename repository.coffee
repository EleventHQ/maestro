AWS           = require 'aws-sdk'
AWS.config.update({region:'us-east-1'})
GitHub        = require 'github'
TokenService  = require './tokenable.js'
YAML          = require 'yamljs'

class Repository
  constructor: (@request)->
    @config = YAML.load './config/github.yml'
    @github = new GitHub(@config.api)

  name: -> @request.post['text']

  execute: ->
    new TokenService('github').then (token)=>
      @github.authenticate type: 'oauth', token: token
      @github.repos.createForOrg
        description: @config.repo.description
        has_downloads: @config.repo.has_downloads
        has_issues: @config.repo.has_issues
        has_wiki: @config.repo.has_wiki
        homepage: @config.repo.homepage.replace('{name}', @name())
        name: @name()
        org: @config.repo.org
        private: @config.repo.private
      
module.exports = Repository

