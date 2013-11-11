Feedbin
=======
[![Code Climate](https://codeclimate.com/github/feedbin/feedbin.png)](https://codeclimate.com/github/feedbin/feedbin)
[![Build Status](https://travis-ci.org/feedbin/feedbin.png?branch=master)](https://travis-ci.org/feedbin/feedbin)

Feedbin is a simple, fast and nice looking RSS reader.

![Feedbin Screenshot](https://raw.github.com/feedbin/feedbin/master/app/assets/images/screenshots/_main.png)

Introduction
------------

Feedbin is a web based RSS reader. It provides a user interface for reading and managing feeds as well as a [REST-like API](https://github.com/feedbin/feedbin-api) for clients to connect to.

If you would like to try Feedbin out you can [sign up](https://feedbin.me/) for an account.

The main Feedbin project is a [Rails 4.0](http://rubyonrails.org/) application. In addition to the main project there are several other services that provide additional functionality. None of these services are required to get Feedbin running locally, but they all provide important functionality that you would want for a production install.

 - [**refresher:**](https://github.com/feedbin/refresher)
   Refresher is the service that does feed refreshing. Feed refreshes are scheduled as background jobs using [Sidekiq](https://github.com/mperham/sidekiq). Refresher is kept separate so it can be scaled independently. It's also a benefit to not have to load all of Rails for this service.
 - [**camo:**](https://github.com/atmos/camo)
   Camo is an https image proxy. In production Feedbin is SSL only. One issue with SSL is all assets must be served over SSL as well or the browser will show insecure content warnings. Camo proxies all image requests through an SSL enabled host to prevent this.

Installation
------------

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

### Pair With Me

Have a feature you would like to add but don't know where to start?

Email [support@feedbin.me](support@feedbin.me) and we'll set something up to work on it together.
