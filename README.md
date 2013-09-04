Feedbin
=======

Feedbin is a simple, fast and nice looking RSS reader. 

![Feedbin Screenshot](https://raw.github.com/feedbin/feedbin/master/app/assets/images/screenshots/_main.png)

Introduction
------------

Feedbin is a web based RSS reader. It provides a user interface for reading and managing feeds as well as a [REST-like API](https://github.com/feedbin/feedbin-api) for clients to connect to.

The main Feedbin project is a [Rails 4.0](http://rubyonrails.org/) application. In addition to the main project there are several other services that provide additional functionality. None of these services are required to get Feedbin running locally, but they all provide important functionality that you would want for a production install.

 - [**refresher:**](https://github.com/feedbin/refresher)
   Refresher is the service that does feed refreshing. Feed refreshes are scheduled as background jobs using [Sidekiq](https://github.com/mperham/sidekiq). Refresher is kept separate so it can be scaled independently. It's also a benefit to not have to load all of Rails for this service.
 - [**polyptych:**](https://github.com/feedbin/polyptych)
   Polyptych is an API for fetching favicons. Favicons are compiled into a singe CSS file as base64 encoded background images. Polyptych is another Rails App. 
 - [**camo:**](https://github.com/atmos/camo)
   Camo is an https image proxy. In production Feedbin is SSL only. One issue with SSL is all assets must be served over SSL as well or the browser will show insecure content warnings. Camo proxies all image requests through an SSL enabled host to prevent this.

Requirements
------------

 - Mac OS X or Linux
 - [Ruby 2.0](http://www.ruby-lang.org/en/)
 - [Postgres 9.2.4](http://www.postgresql.org/)
 - [Redis 2.6.13](http://redis.io/)

Installation
-------------
Ultimately you need a Ruby environment and a Rack compatible application server. For development [Pow](http://pow.cx/) is recommended.

Feedbin uses environment variables for configuration. Feedbin will run without any of these, but various features and functionality will be turned off.

| Environment Variable     | Description                                                                        |
|--------------------------|------------------------------------------------------------------------------------|
| ASSET_HOST               | Pull CDN URL                                                                       |
| AWS_ACCESS_KEY_ID        | Used for file uploads - http://aws.amazon.com                                      |
| AWS_S3_BUCKET            | Used for file uploads - http://aws.amazon.com                                      |
| AWS_SECRET_ACCESS_KEY    | Used for file uploads - http://aws.amazon.com                                      |
| CAMO_HOST                | CDN to point to the camo host                                                      |
| CAMO_KEY                 | Used to rewrite assets to use https - https://github.com/atmos/camo                |
| DATABASE_URL             | Database connection string - postgres://USER:PASS@IP:PORT/DATABASE                 |
| DEFAULT_URL_OPTIONS_HOST | Mailer host - feedbin.me                                                           |
| FEEDBIN_HOMEPAGE_REPO    | Git URL to a Rails engine that provides a custom homepage                          |
| FROM_ADDRESS             | Used as a reply-to email address                                                   |
| GAUGES_SITE_ID           | [gaug.es](http://gaug.es) analytics identifier                                     |
| HONEYBADGER_API_KEY      | Used for error reporting - http://honeybadger.io                                   |
| LIBRATO_SOURCE           | Default source for metrics - feedbin                                               |
| LIBRATO_TOKEN            | Used for reporting stats - http://metrics.librato.com                              |
| LIBRATO_USER             | Used for reporting stats - http://metrics.librato.com                              |
| MEMCACHED_HOSTS          | Comma separated memcached hosts/ports - 192.168.1.2:11121                          |
| POLYPTYCH_CDN            | Used for retrieving and serving favicons - https://github.com/feedbin/polyptych    |
| POLYPTYCH_URL            | Used for retrieving and serving favicons - https://github.com/feedbin/polyptych    |
| POSTGRES_USERNAME        | Used for connecting to database                                                    |
| POSTMARK_API_KEY         | Used for sending email - http://postmarkapp.com                                    |
| RACK_ENV                 | Environment - production                                                           |
| RAILS_ENV                | Environment - production                                                           |
| READABILITY_API_TOKEN    | Used for Readability - http://www.readability.com                                  |
| REDIS_URL                | redis connection string - redis://redis:PASSWORD@192.168.1.3:6379                  |
| SECRET_KEY_BASE          | Encryptions key for Rails - run `rake secret`                                      |
| SIDEKIQ_PASSWORD         | Sidekiq Basic Auth Password                                                        |
| STRIPE_API_KEY           | Used for communicating with stripe - https://stripe.com                            |
| STRIPE_PUBLIC_KEY        | Used for communicating with stripe - https://stripe.com                            |

These variables need to be available in the environment of the user running the app.

Locally I use [dotenv](https://github.com/bkeepers/dotenv) combined with [pow](http://pow.cx/). Pow's `.powenv` file is set up to read dotenv's .env file like:

```shell
export $(cat .env)
```

This is necessary so the environment variables can be read by both Pow and Unicorn.

In production environment variables are set in the `app` users ~/.bash_profile like: 

```shell
export AWS_ACCESS_KEY_ID=aoisjf3j23oij23f
...
```

###Mac OS X Install

This will get Feedbin running on a fresh Mountain Lion install. If you already have a ruby environment configured you can skip most of these steps.

**Command Line Tools (OS X Mountain Lion)**
 
 These can be downloaded from the [Apple Developer website](https://developer.apple.com/downloads/index.action), or in XCode preferences.
		
**Homebrew**
 
    ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go)"

**rbenv**
 
    brew update
    brew install rbenv
    brew install ruby-build
    echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bash_profile
    source ~/.bash_profile

**Ruby 2.0**
 
    rbenv install 2.0.0-p247
    rbenv global 2.0.0-p247

**Bundler**
 
    gem install bundler

**Postgres 9.2.4**
   
    cd ~/Downloads
    curl -L http://postgresapp.com/download > postgres.zip
    unzip postgres.zip
    mv Postgres.app /Applications/
    open /Applications/Postgres.app
   
**Redis 2.6.14**
 
    brew update
    brew install redis

Make sure to follow post install instructions.
	 
**Clone Feedbin**
 
    git clone https://github.com/feedbin/feedbin.git
    cd feedbin
    bundle

**Setup the database**

    rake db:setup
		
**Start scheduled tasks and background workers**

    bundle exec foreman start
		
**[pow](http://pow.cx)**
  
    curl get.pow.cx | sh
    ln -nfs /path/to/feedbin ~/.pow/feedbin

At this point you should be able to load [feedbin.dev](http://feedbin.dev/) in your browser.

###Ubuntu 12.04 Dependencies
 
    apt-get install -y python-software-properties
    add-apt-repository -y ppa:pitti/postgresql
    apt-get -y update
    apt-get -y upgrade
    apt-get install -y build-essential curl libreadline-dev libcurl4-gnutls-dev libpq-dev libxml2-dev libxslt1-dev libcurl4-gnutls-dev zlib1g-dev libssl-dev postgresql-client-9.2

TODO: Getting the Ruby environment setup on Ubuntu and running Feedbin

###Fedora 19 Install

####Feedbin Dependencies

Install a bunch of dependencies:

    sudo yum -y install gcc gcc-c++ git libcurl-devel libxml2-devel libxslt-devel postgresql postgresql-devel rubygems ruby-devel rubygem-bundler

Get Feedbin:

    git clone https://github.com/feedbin/feedbin.git

Install Ruby dependencies:

    cd feedbin
    bundle

####PostgreSQL Server

Make sure your locale uses UTF-8 or you'll get errors at the rake db:setup step:

    sudo nano /etc/locale.conf
    # Make sure the LANG ends with .UTF-8
    # For example, mine looks like:
    #
    #     LANG="en_US.UTF-8"

After changing this file, it's probably a good idea to open a new terminal to make sure the changes get picked up.

Install PostgreSQL:

    sudo yum -y install postgresql-server postgresql-contrib
    sudo postgresql-setup initdb

Remove all authentication by changing `/var/lib/pgsql/data/pg_hba.conf` so
the `127.0.0.1/32` and `::1/128` lines look like this:

    # IPv4 local connections:
    host    all             all             127.0.0.1/32            trust
    # IPv6 local connections:
    host    all             all             ::1/128                 trust

**On a real server, you should *not* do this, as it removes *all* security
from PostgreSQL.** For a real server, change those lines to end with `md5` and
use passwords. You can setup database passwords in config/database.yml.

You can open the file as an admin by running `sudo nano /var/lib/pgsql/data/pg_hba.conf` or `sudo gedit /var/lib/pgsql/data/pg_hba.conf`.

Start the service:

    sudo systemctl start postgresql

    # If you want PostgreSQL to auto-start:
    sudo systemctl enable postgresql

Create a PostgreSQL users:

    sudo -u postgres createuser feedbin
    # You might get output like:
    # could not change directory to "/home/brendan/feedbin"
    # You can safely ignore this.

    # Make yourself a PostgreSQL admin
    sudo -u postgres createuser -s $USER

Setup databases:

    # In the feedbin directory
    rake db:setup

####Redis Server

Install:

    sudo yum install redis

Start the service:

    sudo systemctl start redis

    # If you want it to auto-start:
    sudo systemctl enable redis

Note: Redis doesn't seem to work on Fedora, but Feedbin works without it.

####Run Feedbin

Run these in the `feedbin` directory:

    bundle exec foreman start

    # In a separate terminal:
    rackup

You should see Feedbin at [localhost:9292](http://localhost:9292).
