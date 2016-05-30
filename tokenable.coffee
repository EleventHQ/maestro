AWS     = require 'aws-sdk'
AWS.config.update({region:'us-east-1'})
YAML    = require 'yamljs'

class Tokenable
  constructor: (@name)->

  # TODO: Throw an error if key does not exist
  encryptedPlaintext: ->
    YAML.load('./config/tokens.yml').tokens[@name] || throw "Cannot find token '#{@name}'"

  params: ->
    params =
      CiphertextBlob: new Buffer(@encryptedPlaintext(), 'base64')

  then: (callback)->
    new AWS.KMS().decrypt @params(), (err, data)->
      console.log err, err.stack if err
      callback data['Plaintext'].toString('ascii')

module.exports = Tokenable

