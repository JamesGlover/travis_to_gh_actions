# Migrating Travis to GH Actions

I was hoping to do this with an automated tool, but things get a bit complicated,
and its probably easier doing manually, at least the first time.

## Basics

GH actions are defined in yml files which live in `.github/workflows`
Unlike travis, gh actions can be split into multiple files. Current plan
is to not go overboard here, for Sequencescape for instance I'm planning:

1. Ruby Tests
2. JS Tests
3. Linting (Maybe split into Ruby/JS)
4. Building

## Converting

Travis sets a load of rules for the whole file, some of which are redundant for
some jobs

- Been trying to get bin/setup fulfilling all pre-installation steps. This means we can use the same
  script for CI, as developer on-boarding.

## A note on docker

I'm avoiding docker for the time being, but its something we could consider in
future, as it will give us more control over the process.

## Basic Ruby template

This is the outline from GH when attempting to create a gh action, with some minor modifications, such as
removing ruby-version (so that it'll use the .ruby-version file)

```yaml
# This workflow uses actions that are not certified by GitHub.
# They are provided by a third-party and are governed by
# separate terms of service, privacy policy, and support
# documentation.
# This workflow will download a prebuilt Ruby version, install dependencies and run tests with Rake
# For more information see: https://github.com/marketplace/actions/setup-ruby-jruby-and-truffleruby

name: Ruby

on:
  push:
    branches: [ master ]
  pull_request:
    branches: [ master ]

jobs:
  test:

    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: 2.7
    - name: Install dependencies
      run: bundle install
    - name: Run tests
      run: bundle exec rake

```

## Steps

1. `mkdir .github`
2. `mkdir .github/workflows`
3. `cd .github/workflows`


### Linting

Setting up linting first, as its quick and has few dependencies. An example
from Sequencescape is shown in examples/lint.yml.

1. `touch lint.yml`
2. Bring in the example config above, and give it a sensible name
3. Replace run tests with:

```yaml
    - name: Run rubocop
      run: bundle exec rubocop
```

4. Ran into issues with Oracle gems, plus, only really need rubocop so added
   following before bundle install:

```yaml
    - name: Configure bundler
      run: bundle config set without 'warehouse cucumber deployment profile development default'
```

Meanwhile I moved the linting gems into a separate group.
(Might end up undoing all of this if I can have a shared setup)

5. Played around with artifacts, but only get a zip file.
6. Looking at rails example:

<https://github.com/rails/rails/blob/4a78dcb326e57b5035c4df322e31875bfa74ae23/.github/workflows/rubocop.yml#L1>

Referenced from here: https://github.com/andrewmcodes/rubocop-linter-action
(Which itself isn't usable in out case, and has a big warning about its suitability)
7. Add caching of gemfile
8. Added caching rubocop cache (although dependent on rubocop update)

Note: Not using the <https://github.com/github/super-linter> as want control over rubocop versions to ensure
same versions used in dev and CI. Otherwise its just a pain keeping the two in sync.

### Testing

1. Use the Linting as a basis, as that'll get us some of the way there.
2. Modify the groups that get installed to include default and testing
3. We still exclude development when running tests. Will need it for building,
   which makes me think we need another group.
4. Will need access to a database

Setup a database service:

```yaml
jobs:
  rake_tests:

    # ...

    # Services
    # https://docs.github.com/en/free-pro-team@latest/actions/reference/workflow-syntax-for-github-actions#jobsjob_idservices
    services:
      mysql:
        # Use the Mysql docker image https://hub.docker.com/_/mysql
        image: mysql:5.7 # Using 5.7 to map to what is used in production.
        ports:
         - 3306 # Default port mappings
         # Monitor the health of the container to mesaure when it is ready
        options: --health-cmd="mysqladmin ping" --health-interval=10s --health-timeout=5s --health-retries=3
        env:
          MYSQL_ROOT_PASSWORD: '' # Set root PW to nothing
          MYSQL_ALLOW_EMPTY_PASSWORD: yes

    # ...
```

Need to then update the database.yml file to take custom port numbers, and then
populate those with the appropriate port:

```yaml
# database.yml
mysql: &MYSQL
  adapter: mysql2
  username: <%= ENV.fetch('DBUSERNAME','root') %>
  password: <%= ENV['DBPASSWORD'] %>
  encoding: utf8
  properties:
    characterSetResults: utf8
  pool: 5
  timeout: 5000
  reaping_frequency: 600
  host: 127.0.0.1
  port: <%= ENV.fetch('DBPORT','3306') %>
  variables:
    sql_mode: TRADITIONAL
    # This improbably large value mimics the global option for production
    # Without this things fall back to 1024 (At least with my setup) which
    # is too small for larger pools.
    group_concat_max_len: 67108864
```

```yaml
    - name: Setup environment
      env:
        DBPORT: ${{ job.services.mysql.ports[3306] }}
      run: |
        bundle config path vendor/bundle
        bundle config set without 'warehouse deployment profile development'
        bin/setup
    # Actually run our tests
    - name: Run rake tests
      env:
        DBPORT: ${{ job.services.mysql.ports[3306] }}
      run: bundle exec rake test
```

5. Travis envs - Fairly easy to bring across
```
env:
  global:
  - TZ=Europe/London
  - CUCUMBER_FORMAT=summary
```

Becomes:
```yaml
env:
  TZ: Europe/London
  CUCUMBER_FORMAT: summary
```

Top level and is shared across all steps/jobs
Meanwhile I also added some of the job specific envs:

```yaml
jobs:
  rake_tests:
    env:
      RAILS_ENV: test
```

6. Migrating before scripts:

In most cases I've been making a few tweaks to the way these work, but in theory
migrating is as simple as

```yaml
    before_script:
    - RAILS_ENV=test bundle exec rails webdrivers:chromedriver:update
    - curl -L https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64 > ./cc-test-reporter
    - chmod +x ./cc-test-reporter
    - "./cc-test-reporter before-build"
```

Would become:
```yaml
  steps:
    - name: Setup environment
      env:
        DBPORT: ${{ job.services.mysql.ports[3306] }}
      run: |
        bundle exec rails webdrivers:chromedriver:update
        curl -L https://codeclimate.com/downloads/test-reporter/test-reporter-latest-linux-amd64 > ./cc-test-reporter
        chmod +x ./cc-test-reporter
        ./cc-test-reporter before-build
```

7. xvfb-run

Headless chrome no longer requires xvfb

## Code coverage

Code coverage with code climate looks to be a pain.

This action seems popular:
https://github.com/marketplace/actions/code-climate-coverage-action

Getting parallel testing working is actually somewhat easier than it may seem:

1. To each test suite add the following step last:
```yaml
    - name: Upload coverage artifact
      uses: actions/upload-artifact@v2
      with:
        name: codeclimate-${{ github.job }}-${{ matrix.ci_node_index }}
        path: coverage/.resultset.json # This is simple cov, you may need to change for other tools
        retention-days: 1
```
This will upload the coverage stats

Note: CodeClimate simple cov support is changing:
https://github.com/codeclimate/test-reporter/issues/413
The simple cov changes have been made, and we're just waiting for code climate to update their side.
Essentially rather than using the internal .resultset.json the new version will use a proper formatter.

2. Add the final json, dependent on the previous ones

```yaml
  end_coverage:
    runs-on: ubuntu-latest
    needs: [rake_tests, rspec_tests, cucumber_tests]
    steps:
    - name: Fetch coverage results
      uses: actions/download-artifact@v2
      with:
        path: tmp/
    - name: Publish code coverage
      uses: paambaati/codeclimate-action@v2.7.5
      env:
        CC_TEST_REPORTER_ID: ${{ secrets.CC_TEST_REPORTER_ID }}
      with:
        coverageLocations: |
          tmp/codeclimate-rake_tests-
          tmp/codeclimate-rspec_tests-0
          tmp/codeclimate-rspec_tests-1
          tmp/codeclimate-rspec_tests-2
          tmp/codeclimate-cucumber_tests-0
          tmp/codeclimate-cucumber_tests-1
```

This downloads all the files uploaded in the previous steps, and then formats, sums and uploads them.

## Building

Here the trickiest aspect is working out how to trigger a release build. In travis we:
- Detected a tag
- Pushed up the release files

And this seemed to work fine. However, the official action requires a release url, which isn't available
(as far as I can tell) for an action triggered by a tag.

Instead I've opted to use the release publish action. This does mean it only works for proper
github releases, not just tags.

```yaml
on:
  release:
    types: published
```

If we want the latter, I believe we can create another action to generate a release from
a tag event.

Actual upload bit:

```yaml
    # https://github.com/marketplace/actions/upload-a-release-asset
    - name: Upload release.gz
      id: upload-release-gz
      uses: actions/upload-release-asset@v1
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      with:
        upload_url: ${{ github.event.release.upload_url }} # Pull the URL from the event
        asset_path: ./release.tar.gz
        asset_name: gh-release.tar.gz
        asset_content_type: application/gzip
```
