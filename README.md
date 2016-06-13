# Maestro

Jarvis, but for Elevent. Easily add Slack commands powered by AWS API Gateway and Lambda.

## Architecture

Maestro is built on top of Claudia.js, which means you'll have to become friends with Node 4.something. 
[Read more about Claudia.js here.](https://github.com/claudiajs/claudia)

The short of it is that at deploy time,
* CoffeeScript compiles our, well, CoffeeScript into JavaScript
* Claudia.js compiles our JavaScript into [AWS Lambda functions](https://aws.amazon.com/lambda/).
* The Claudia API Builder configures the [AWS API Gateway](https://aws.amazon.com/api-gateway/) on top of our Lambda functions.
* The latest code becomes available at https://ellie.eleventhq.com/latest/
* Slack, GitHub, and potentially other services communicate with our functions through that endpoint, mostly via webhooks.

If you want a quick sanity check, you can go to the [/echo](https://ellie.eleventhq.com/latest/echo) endpoint and see what's up.

We do some clever stuff to get the vanity ellie.eleventhq.com URL on top of the API gateway. There's a CloudFront instance on top of it you should check out. Also some custom SSL stuff I don't really remember, I think it was with the AWS Certificate Manager.

## Available Functionality

Please see `app.coffee` for the canonical list of endpoints.

* `/`: hello world
* `/echo`: debug the current request
* `/encrypt`: encrypt the current POST text parameter with Ellie's public key, stored in [AWS Key Management Service](http://aws.amazon.com/kms/).
* `/github/events`: Receives GitHub organization webhook events. [We configure that here](https://github.com/organizations/EleventHQ/settings/hooks). You may need to log in as [@Elliebot](https://github.com/elliebot); password is in 1Password. Talk to [@EleventHQ/operations](https://github.com/orgs/EleventHQ/teams/operations) if you don't have access and need it.
* `/labelize`: Slack command. Reapplies our labeling scheme to a GitHub repository. Configure this in `config/github.labels.yml`.
* `/repository`: Slack command. Create a new repository. Defaults are configured in `config/github.yml`.
* `/version`: Get the current version.


