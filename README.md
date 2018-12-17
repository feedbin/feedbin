Feedbin
=======

Feedbin is a simple, fast and nice looking RSS reader.

![Feedbin Screenshot](https://feedbin.github.io/files/feedbin_screenshot.jpeg)

Introduction
------------

Feedbin is a web based RSS reader. It provides a user interface for reading and managing feeds as well as a [REST-like API](https://github.com/feedbin/feedbin-api) for clients to connect to.

If you would like to try Feedbin out you can [sign up](https://feedbin.com/) for an account.

The main Feedbin project is a [Rails 5](http://rubyonrails.org/) application. In addition to the main project there are several other services that provide additional functionality. None of these services are required to get Feedbin running locally, but they all provide important functionality that you would want for a production install.

 - [**refresher:**](https://github.com/feedbin/refresher)
   Refresher is the service that does feed refreshing. Feed refreshes are scheduled as background jobs using [Sidekiq](https://github.com/mperham/sidekiq). Refresher is kept separate so it can be scaled independently. It's also a benefit to not have to load all of Rails for this service.
 - [**image:**](https://github.com/feedbin/image)
   Image is the service that finds images to be [associated with articles](https://feedbin.com/blog/2015/10/22/image-previews/)
 - [**camo:**](https://github.com/atmos/camo)
   Camo is an https image proxy. In production Feedbin is SSL only. One issue with SSL is all assets must be served over SSL as well or the browser will show insecure content warnings. Camo proxies all image requests through an SSL enabled host to prevent this.

Requirements
------------

 - Mac OS X or Linux
 - [Ruby 2.3.1](http://www.ruby-lang.org/en/)
 - [Postgres 10](http://www.postgresql.org/)
 - [Redis > 2.8](http://redis.io/)
 - [Memcached](https://memcached.org/)
 - [Elasticsearch 2.4.X](https://www.elastic.co/downloads/past-releases/elasticsearch-2-4-5)

Installation
-------------
Ultimately, you'll need a Ruby environment and a Rack compatible application server. For development [Pow](http://pow.cx/) is recommended.

First, install the dependencies listed under requirements.

Next clone the repository and install the application dependencies

    git clone https://github.com/feedbin/feedbin.git
    cd feedbin
    bundle

If you encounter any errors after running `bundle` there is a problem installing one of the dependencies. You must find out how to get this dependency installed on your platform.

**Configure**

Feedbin uses environment variables for configuration. Feedbin will run without most of these, but various features and functionality will be turned off.

Rename [.env.example](.env.example) to `.env` and customize it with your settings.

**Setup the database**

    rake db:setup

**Start the processes**

    bundle exec foreman start


Status Badges
-------------
[![Build Status](https://travis-ci.org/feedbin/feedbin.svg?branch=master)](https://travis-ci.org/feedbin/feedbin)

[![Code Climate](https://codeclimate.com/github/feedbin/feedbin.svg)](https://codeclimate.com/github/feedbin/feedbin)

[![Coverage Status](https://coveralls.io/repos/github/feedbin/feedbin/badge.svg)](https://coveralls.io/github/feedbin/feedbin)
