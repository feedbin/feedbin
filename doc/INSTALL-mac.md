Feedbin Installation on Mac OS X Mountain Lion
----------------------------------------------

This will get Feedbin running on a fresh Mountain Lion install. If you already have a ruby environment configured you can skip most of these steps.

#### Command Line Tools (OS X Mountain Lion)

These can be downloaded from the [Apple Developer website](https://developer.apple.com/downloads/index.action), or in XCode preferences.

#### Homebrew

    ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go)"

#### rbenv

    brew update
    brew install rbenv
    brew install ruby-build
    echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bash_profile
    source ~/.bash_profile

#### Ruby 2.0

    rbenv install 2.0.0-p247
    rbenv global 2.0.0-p247

#### Bundler

    gem install bundler

#### Postgres 9.2.4

    cd ~/Downloads
    curl -L http://postgresapp.com/download > postgres.zip
    unzip postgres.zip
    mv Postgres.app /Applications/
    open /Applications/Postgres.app

#### Redis 2.6.14

    brew update
    brew install redis

Make sure to follow post install instructions.

#### Clone Feedbin

    git clone https://github.com/feedbin/feedbin.git
    cd feedbin
    bundle

#### Setup the database

    rake db:setup

#### Start scheduled tasks and background workers

    bundle exec foreman start

#### [pow](http://pow.cx)

    curl get.pow.cx | sh
    ln -nfs /path/to/feedbin ~/.pow/feedbin

At this point you should be able to load [feedbin.dev](http://feedbin.dev/) in your browser.