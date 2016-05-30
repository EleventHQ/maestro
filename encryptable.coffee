# Encryptable
# Easily encrypt a string against Ellie's public key,
# so she can decrypt it server-side later.
# You can run `/encrypt hello world` from Slack, and then paste the resulting encrypted text
# into `tokens.yml` in this repo (maestro) to reference later.

AWS   = require 'aws-sdk'
YAML  = require 'yamljs'

class Encryptable
  constructor: (@request)->

  execute: ->
    new AWS.KMS().encrypt(@params()).promise().then (data)->
      data.CiphertextBlob.toString('base64')

  params: ->
    params =
      KeyId: YAML.load('./config/tokens.yml').key
      Plaintext: @request.post['text']

module.exports = Encryptable

