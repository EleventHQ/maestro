CircleCI      = require './circle.js'
GitHub        = require 'github'
Labelize      = require './labelize.js'
Promise       = require 'promise'
TokenService  = require './tokenable.js'
YAML          = require 'yamljs'

class GitHubEventHandler
  constructor: (@request)->
    @config = YAML.load './config/github.yml'
    @github = new GitHub(@config.api)

  authenticate: (token)=>
    new Promise (fulfill, reject)=>
      @github.authenticate type: 'oauth', token: token

  automaticallyDeleteBranchesForMergedPullRequests: =>
    @_watchForMergedPullRequests (fulfill)=>
      @github.gitdata.deleteReference
        user: @request.body.pull_request.head.repo.owner.login
        repo: @request.body.pull_request.head.repo.name
        ref:  "heads/#{@request.body.pull_request.head.ref}"
      , fulfill

  execute: ->
    new TokenService('github').
      then(@authenticate).
      then(@openPullRequest).
      then(@automaticallyDeleteBranchesForMergedPullRequests).
      then(@removeInProgressLabelFromMergedPullRequests).
      then(@labelizeCreatedRepositories).
      then(@followCreatedRepositoriesOnCircle).
      then(@addDefaultTeams).
      then(@mergeSuccessfulBuildsWithMergeFlag).
      then(@propagateStyleGuideChangesToOtherRepos)

  addDefaultTeams: =>
    @_watch 'repository', action: 'created', (fulfill)=>
      Promise.all @config.teams.map (team)=> new Promise (fulfill, reject)=>
        params =
          id: team.id
          org: @config.repo.org
          repo: @request.body.repository.name
          permission: team.permission

        @github.orgs.addTeamRepo params, (err, result)=>
          console.log err if err
          console.log result
          fulfill()

  followCreatedRepositoriesOnCircle: =>
    @_watch 'repository', action: 'created', (fulfill)=>
      new CircleCI(@request.body.repository.name).execute().then(fulfill)

  labelizeCreatedRepositories: =>
    @_watch 'repository', action: 'created', (fulfill)=>
      new Labelize(post: { text: @request.body.repository.name }).execute().then(fulfill)

  # If your commit message includes [merge], then Ellie will merge your pull request automatically,
  # once your status checks pass
  mergeSuccessfulBuildsWithMergeFlag: =>
    # TODO: Will need more cleverness to support multiple status checks
    @_watch 'status', context: 'ci/circleci', state: 'success', (fulfill)=>
      return fulfill() unless @request.body.commit.commit.message.indexOf('[merge]') > -1

      Promise.all @request.body.branches.map (branch)=> new Promise (fulfill, reject)=>
        console?.log "Branch: #{JSON.stringify branch}"
        payload =
          user: @request.body.repository.owner.login
          repo: @request.body.repository.name
          filter: branch.name
        @github.pullRequests.getAll payload, (err, pullRequests)=>
          console?.log "err: #{err}" if err
          console?.log "pullRequests: #{JSON.stringify pullRequests}"
          Promise.all pullRequests.map (pullRequest)=> new Promise (fulfill, reject)=>
            payload =
              user: @request.body.repository.owner.login
              repo: @request.body.repository.name
              number: pullRequest.number
              sha: @request.body.commit.sha # must match succesful status check
            console?.log "Payload: #{JSON.stringify payload}"
            @github.pullRequests.merge payload, (err, response)=> fulfill()
          , fulfill

      , fulfill

  # Automatically open a pull request when we push a new branch.
  # * Automatically opens a pull request when a new branch is pushed.
  # * Labels the pull request with any hashtags found in the commit message (like #bug)
  # * Labels the pull request with the platform found in `.github/PLATFORM` (if present)
  # * Labels the pull request with the kind of addition it is based on the branch name (
  # * Labels the pull request `in progress`
  # * Assigns the author
  #
  # TODO:
  # * Do not open a pull request against master
  # * Do not open a pull request against $ARBITRARY_BRANCH_NAMES? (.github/ configuration?)
  # * Milestone management from commit message?
  openPullRequest: =>
    @_watch 'create', ref_type: 'branch', (fulfill)=>
      branchName = @request.body.ref.split('-')[0]
      pullRequest =
        body: ''
        labels: ['in progress', branchName]
        title: 'WIP'

      @_getContent '.github/SKIP_AUTOMATIC_PULL_REQUEST_BRANCHES', (err, _r, skipAutomaticPullRequestBranches)=>
        unless err
          branchIsIgnored = false
          skipAutomaticPullRequestBranches.split("\n").forEach (branch)=>
            branchIsIgnored = true if branch == branchName
          return fulfill() if branchIsIgnored

        console.log 'READY FOR THE PROMISES'

        promises    = []
        promises.push new Promise (fulfill, reject)=>
          console.log "Looking up labels against commit"
          getReferenceParams =
            user: @request.body.repository.owner.login
            repo: @request.body.repository.name
            ref: "heads/#{@request.body.ref}"

          @github.gitdata.getReference getReferenceParams, (err, reference)=>
            console.log err if err
            console.log reference
            @github.gitdata.getCommit
              user: @request.body.repository.owner.login
              repo: @request.body.repository.name
              sha: reference.object.sha
            , (err, commit)=>
              console.log err if err
              console.log commit
              # Get hashtags
              commit.message.split(' ').forEach (word)=>
                pullRequest.labels.push(word.substring(1)) if word.indexOf('#') == 0
              pullRequest.title = commit.message.split("\n")[0]
              fulfill()

        promises.push new Promise (fulfill, reject)=>
          console.log "Looking up PLATFORM"
          @_getContent '.github/PLATFORM', (err, result, contents)=>
            unless err
              pullRequest.labels.push(contents.split("\n")[0])
            fulfill()

        promises.push new Promise (fulfill, reject)=>
          console.log "Looking up PULL REQUEST TEMPLATE"
          @_getContent '.github/PULL_REQUEST_TEMPLATE.md', (err, _r, contents)=>
            pullRequest.body = contents
            fulfill()

        Promise.all(promises).then => new Promise (created, failed)=>
          console.log "Creating Pull Request"
          payload =
            user: @request.body.repository.owner.login
            repo: @request.body.repository.name
            head: @request.body.ref
            base: @request.body.master_branch
            title: pullRequest.title # First line of commit message
            body: pullRequest.body
          console.log "Payload: #{JSON.stringify payload}"
          @github.pullRequests.create payload, (err, result)=>
            console.log(err) if err
            console.log "Created Pull Request: #{JSON.stringify result}"
            console.log "Labels: #{JSON.stringify pullRequest.labels}"
            getLabelsPayload =
              user: @request.body.repository.owner.login
              repo: @request.body.repository.name
              per_page: 100 # 100 is max
            @github.issues.getLabels getLabelsPayload, (err, availableRepositoryLabels)=>
              console.log err if err

              pullRequest.labels.forEach (label, index)=>
                labelIsPresentWithinAvailableLabels = false
                availableRepositoryLabels.forEach (remoteLabelObject)=>
                  labelIsPresentWithinAvailableLabels = true if remoteLabelObject.name == label
                pullRequest.labels.splice(index, 1) unless labelIsPresentWithinAvailableLabels

              updateIssuePayload =
                user: @request.body.repository.owner.login
                repo: @request.body.repository.name
                number: result.number
                assignee: @request.body.sender.login
                labels: pullRequest.labels

              @github.issues.edit updateIssuePayload, (err, updateIssuePayload)=>
                console.log err if err
                console.log updateIssuePayload
                fulfill()
                created()
        .then => console.log 'Did all the things'

  propagateStyleGuideChangesToOtherRepos: =>
    @_watch 'push', ref: 'refs/heads/master', (fulfill)=>
      return fulfill() unless @request.body.repository.name == 'style-guide'

      changedFiles = []

      @request.body.commits.forEach (commit)=>
        ['added', 'removed', 'modified'].forEach (event)=>
          commit[event].forEach (file)=>
            if file.split('/')[0] == 'shared'
              unless changedFiles.indexOf(file) > -1
                changedFiles.push file
      
      Promise.all changedFiles.map (changedFile)=> new Promise (fulfill, reject)=>
        # Since we're always copying master from style-guide, this works great
        @_getContent changedFile, (err, changedFileContents)=>
          @github.repos.getAll (repositories)=>
            Promise.all repositories.map (repository)=> new Promise (fulfill, reject)=>
              return fulfill() if repository.name == 'style-guide' # don't re-push, oh no
              payload =
                user: @request.body.repository.owner.login
                repo: @request.body.repository.name
                path: changedFile
                message: "Adds #{changedFile.split('/')[1]} from @EleventHQ/style-guide\n\n[merge]"
                content: changedFileContents
                branch: 'chore-propagates-style-guide'
                committer: commit.committer
              console?.log payload
              @github.repos.createFile payload, (err, response)=> fulfill()
            .then(fulfill)

      , (fulfill)=>

        

  removeInProgressLabelFromMergedPullRequests: =>
    @_watchForMergedPullRequests (fulfill)=>
      @github.issues.removeLabel
        user: @request.body.pull_request.head.repo.owner.login
        repo: @request.body.pull_request.head.repo.name
        number: @request.body.pull_request.number
        name: 'in progress'
      , fulfill

  _isEvent: (event)=> @request.headers['X-GitHub-Event'] == event

  _getContent: (path, callback)=>
    lookupParams =
      user: @request.body.repository.owner.login
      repo: @request.body.repository.name
      path: path

    @github.repos.getContent lookupParams, (err, result)=>
      console.log err if err
      console.log "getContent: #{path}, result: #{JSON.stringify result}"
      content = new Buffer(result?.content || '', 'base64').toString('ascii')
      callback(err, result, content)
  
  _matchesConditions: (conditions)=>
    matches = false
    Object.keys(conditions).forEach (key)=>
      matches = true if @request.body[key] == conditions[key]
    matches

  _watch: (event, conditions, action)=>
    new Promise (fulfill, reject)=>
      if @_isEvent(event) && @_matchesConditions(conditions)
        console.log "Executing action on #{event}, #{JSON.stringify conditions}"
        action(fulfill)
      else
        fulfill()

  _watchForMergedPullRequests: (action)=>
    @_watch 'pull_request', action: 'closed', (fulfill)=>
      if @request.body.pull_request.merged_at
        action(fulfill)
      else
        fulfill()

module.exports = GitHubEventHandler

