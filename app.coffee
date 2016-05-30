ApiBuilder  = require 'claudia-api-builder'
api         = new ApiBuilder()
FS          = require 'fs'
Encryptable = require './encryptable.js'

module.exports = api

api.get  '/',                  -> 'hello world'
api.get  '/echo',     (request)-> request
api.post '/echo',     (request)-> request
api.post '/encrypt',  (request)-> new Encryptable(request).execute()
api.get  '/version',           -> JSON.parse FS.readFileSync('./package.json').version

