Feedbin Installation on Mac OS X
----------------------------------------------

This will get Feedbin running on a fresh install. If you already have a ruby environment configured you can skip most of these steps.

#### Command Line Tools

These can be downloaded from the [Apple Developer website](https://developer.apple.com/downloads/index.action), or in Xcode preferences.

#### Homebrew

    ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go)"

#### rbenv

    brew update
    brew install rbenv
    brew install ruby-build
    echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bash_profile
    source ~/.bash_profile

#### Ruby 2.3.1

    rbenv install 2.3.1
    rbenv global 2.3.1

#### Bundler

    gem install bundler

You may need to open a new terminal to make the `bundle` command available in your `PATH`.

#### Postgres 9.2.4

    brew install caskroom/cask/brew-cask
    brew cask install postgres
    open ~/Applications/Postgres.app

#### Redis 2.6.14

    brew update
    brew install redis
    redis-server

#### ImageMagick (requirement for rmagick gem)

    brew update
    brew install ImageMagick

Make sure to follow post install instructions.

#### Clone Feedbin

    git clone https://github.com/feedbin/feedbin.git
    cd feedbin
    bundle

#### Setup the database (Make sure you're running Postgres and Redis)

    rake db:setup

#### Start scheduled tasks and background workers

    bundle exec foreman start

#### [pow](http://pow.cx)

    curl get.pow.cx | sh
    ln -nfs /path/to/feedbin ~/.pow/feedbin

At this point you should be able to load [feedbin.dev](http://feedbin.dev/) in your browser.
