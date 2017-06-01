Feedbin
=======
[![Build Status](https://travis-ci.org/feedbin/feedbin.svg?branch=master)](https://travis-ci.org/feedbin/feedbin)
[![Code Climate](https://codeclimate.com/github/feedbin/feedbin.svg)](https://codeclimate.com/github/feedbin/feedbin)
[![Coverage Status](https://coveralls.io/repos/github/feedbin/feedbin/badge.svg)](https://coveralls.io/github/feedbin/feedbin)

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
 - [Postgres 9.2.4](http://www.postgresql.org/)
 - [Redis > 2.8](http://redis.io/)

Installation
-------------
Ultimately, you'll need a Ruby environment and a Rack compatible application server. For development [Pow](http://pow.cx/) is recommended.

Feedbin uses environment variables for configuration. Feedbin will run without these, but various features and functionality will be turned off.

| Environment Variable     | Description                                                                        |
|--------------------------|------------------------------------------------------------------------------------|
| ASSET_HOST               | Pull CDN URL                                                                       |
| AWS_ACCESS_KEY_ID        | Used for file uploads - http://aws.amazon.com                                      |
| AWS_S3_BUCKET            | Used for file uploads - http://aws.amazon.com                                      |
| AWS_SECRET_ACCESS_KEY    | Used for file uploads - http://aws.amazon.com                                      |
| CAMO_HOST                | CDN to point to the camo host                                                      |
| CAMO_KEY                 | Used to rewrite assets to use https - https://github.com/atmos/camo                |
| DATABASE_URL             | Database connection string - postgres://USER:PASS@IP:PORT/DATABASE                 |
| DEFAULT_URL_OPTIONS_HOST | Mailer host - feedbin.com                                                          |
| ELASTICSEARCH_URL        | search endpoint - http://localhost:9200                                            |
| ENTRY_LIMIT              | Maximum entries per feed. Older entries will be deleted.                           |
| FEEDBIN_HOMEPAGE_REPO    | Git URL to a Rails engine that provides a custom homepage                          |
| FROM_ADDRESS             | Used as a reply-to email address                                                   |
| GAUGES_SITE_ID           | [gaug.es](http://gaug.es) analytics identifier                                     |
| HONEYBADGER_API_KEY      | Used for error reporting - http://honeybadger.io                                   |
| LIBRATO_SOURCE           | Default source for metrics - feedbin                                               |
| LIBRATO_TOKEN            | Used for reporting stats - http://metrics.librato.com                              |
| LIBRATO_USER             | Used for reporting stats - http://metrics.librato.com                              |
| MEMCACHED_HOSTS          | Comma separated memcached hosts/ports - 192.168.1.2:11121                          |
| POSTGRES_USERNAME        | Used for connecting to database                                                    |
| POSTGRES_HOST            | Used for connecting to database                                                    |
| POSTGRES_PASSWORD        | Used for connecting to database                                                    |
| PUSH_URL                 | URL for the Feedbin instance - https://feedbin.com                                 |
| RACK_ENV                 | Environment - production                                                           |
| RAILS_ENV                | Environment - production                                                           |
| READABILITY_API_TOKEN    | Used for Readability - http://www.readability.com                                  |
| REDIS_URL                | redis connection string - redis://redis:PASSWORD@192.168.1.3:6379                  |
| SECRET_KEY_BASE          | Encryptions key for Rails - run `rake secret`                                      |
| SIDEKIQ_PASSWORD         | Sidekiq Basic Auth Password                                                        |
| SMTP_ADDRESS             | SMTP Host                                                                          |
| SMTP_USERNAME            | SMTP Username                                                                      |
| SMTP_PASSWORD            | SMTP Password                                                                      |
| STRIPE_API_KEY           | Used for communicating with stripe - https://stripe.com                            |
| STRIPE_PUBLIC_KEY        | Used for communicating with stripe - https://stripe.com                            |
| ANALYTICS_ID             | Google Analytics Property                                                          |
| ANALYTICS_DOMAIN         | Google Analytics Domain                                                            |
| EVERNOTE_KEY             | Evernote API Key                                                                   |
| EVERNOTE_SECRET          | Evernote API Secret                                                                |

These variables will need to be available in the environment of the user running the app.

### Feedbin Install Guides

- [Mac OS X](doc/INSTALL-mac.md)
- [Ubuntu](doc/INSTALL-ubuntu.md) (incomplete)
- [Fedora](doc/INSTALL-fedora.md)
