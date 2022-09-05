Feedbin
=======

Feedbin is a simple, fast and nice looking RSS reader.

![Feedbin Screenshot](https://feedbin.github.io/files/feedbin-screenshot.jpeg)

Support
-------

Support for Feedbin customers is available by emailing [support@feedbin.com](mailto:support@feedbin.com). No support is provided for installing/running Feedbin.

Introduction
------------

Feedbin is a web based RSS reader. It provides a user interface for reading and managing feeds as well as a [REST-like API](https://github.com/feedbin/feedbin-api) for clients to connect to.

Feedbin's goal is to be a great web-based RSS service. This goal is at odds with being a great self-hosted RSS reader. There are a lot of moving parts and things to configure, so for that reason I do not recommend that you run Feedbin in production.

If you're looking for a self-hosted RSS reader check out:

- [yarr](https://github.com/nkanaev/yarr)
- [Tiny Tiny RSS](https://tt-rss.org)
- [Fresh RSS](https://freshrss.org)

And if you really want to run the whole Feedbin stack, take a look at this [Docker version](https://github.com/angristan/feedbin-docker). If you would like to try Feedbin out you can [sign up](https://feedbin.com/) for an account.

The main Feedbin project is a [Rails 6](http://rubyonrails.org/) application. In addition to the main project there are several other services that provide additional functionality. None of these services are required to get Feedbin running locally, but they all provide important functionality that you would want for a production install.

 - [**crawler:**](https://github.com/feedbin/crawler)
   Crawler is the service that does feed refreshing and image processing. Crawler is kept separate so it can be scaled independently. It's also a benefit to not have to load all of Rails for this service.
   
**Optional services**
 
 - [**Privacy Please:**](https://github.com/feedbin/privacy-please)
   Privacy Please is an https image proxy. In production Feedbin is TLS only. One issue with TLS is all assets must be served over TLS as well or the browser will show insecure content warnings. Privacy Please proxies all image requests through an TLS enabled host to prevent this. Using a proxy has the added benefit of providing privacy while using Feedbin.
 - [**extract:**](https://github.com/feedbin/extract)
   Extract is a Node.js service that extract content from web pages. It is used to extract full pages when a feed only provide excerpts.

Requirements
------------

 - Mac OS X or Linux
 - [Ruby 3.1](http://www.ruby-lang.org/en/)
 - [Postgres 11](http://www.postgresql.org/)
 - [Redis > 6.0](http://redis.io/)
 - [Elasticsearch 2.4](https://www.elastic.co/downloads/past-releases/#elasticsearch)

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
![Ruby CI](https://github.com/feedbin/feedbin/workflows/Ruby%20CI/badge.svg)

[![Code Climate](https://codeclimate.com/github/feedbin/feedbin.svg)](https://codeclimate.com/github/feedbin/feedbin)
