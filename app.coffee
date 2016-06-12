ApiBuilder          = require 'claudia-api-builder'
api                 = new ApiBuilder()
FS                  = require 'fs'
Encryptable         = require './encryptable.js'
GitHubEventHandler  = require './github_event_handler.js'
Labelize            = require './labelize.js'

module.exports = api

api.get  '/',                        -> 'hello world'
api.get  '/echo',           (request)-> request
api.post '/echo',           (request)-> request
api.post '/encrypt',        (request)-> new Encryptable(request).execute()
api.post '/github/events',  (request)-> new GitHubEventHandler(request).execute()
api.post '/labelize',       (request)-> new Labelize(request).execute()
api.get  '/version',                 -> JSON.parse(FS.readFileSync('./package.json')).version

