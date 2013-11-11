Installing Feedbin on a Debian 7.0 (Wheezy) System.
===================================================

Get Ruby 2.0
------------

As of November 2013, most Ubuntu and Debian distributions do not yet have Ruby 2.0 packaged by default.  We recommend using `rbenv` with `ruby-build` to get Ruby 2.0 -- however, for various reasons, doing that through the `apt-get` package management system won't work, so just do it the old-fashioned way:

        $ sudo adduser feedbin --disabled-password
        $ sudo su - feedbin
        $ git clone git://github.com/sstephenson/rbenv.git ~/.rbenv
        $ echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
        $ echo 'eval "$(rbenv init -)"' >> ~/.bashrc
        $ exec $SHELL  ### (or log out and log back in) ###
        $ mkdir ~/.rbenv/plugins
        $ git clone git://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
        $ exec $SHELL  ### (or log out and log back in) ###
        $ rbenv install 2.0.0-p247
        ### (this may take a while to complete) ###
        $ rbenv global 2.0.0-p247
        $ gem install bundler

Get Postgres 9.2.4 or higher
----------------------------

As of November 2013, most Ubuntu and Debian distributions do not yet have PostgreSQL 9.2 or higher packaged (they're still on 9.1). Fortunately the PostgreSQL project itself maintains packages that you can install directly.  So:

        $ sudo vi /etc/apt/sources.list.d/pgdg.list
        ### Now add a line like this to that (possibly new) file:
        ###
        ###   deb http://apt.postgresql.org/pub/repos/apt/ wheezy-pgdg main
        ###
        ### ...where "wheezy" might be "squeeze" or whatever the
        ### appropriate code name for your distribution is.  (On
        ### Debian, `lsb_release -c` will tell you the right name.)

        $ wget http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc
        ### Do whatever you'd like with GnuPG, various Internet search
        ### engines, etc, to verify that the key in ACCC4CF8.asc
        ### really is the PostgreSQL distribution key.  (Those steps
        ### are beyond the scope of this document.  If you don't know
        ### what they might be, you could skip them, but at the very
        ### least enter "ACCC4CF8" into a search engine and check that
        ### the results that come up indicate that it is a legitimate
        ### PostgreSQL distribution key, and make sure no one's
        ### shouting warnings that it's a fake.)

        $ sudo apt-key add ACCC4CF8.asc
        $ apt-get install postgresql-9.3 pgadmin3

Get Redis 2.6.13 or higher
--------------------------

As of November 2013, most Ubuntu and Debian distributions do not yet have Redis 2.6.13, or for that matter even 2.0 or higher.  You'll need to download and build it yourself:

        $ wget http://download.redis.io/releases/redis-2.6.16.tar.gz
        ### (Or whatever the highest stable build is as listed on
        ### http://redis.io/download -- it was 2.6.16 as of this writing.)
        
        $ zcat redis-2.6.16.tar.gz | tar xvf -
        $ cd redis-2.6.16
        $ make
        ### Note you might need to do `apt-get install tcl` before
        ### `make test`, as the test suite requires TCL 8.5 or higher:
        $ make test
        $ sudo make install
        
        ### Since one could theoretically have multiple Redis instances
        ### running on a server, each inctance listening on its own port,
        ### some people name the conf files after the port numbers, e.g.,
        ### `/etc/redis/redis-6379.conf` (port 6379 is the default port for
        ### Redis anyway).  We're not using multiple conf files here, since
        ### we assume that there will only be one instance of Redis running
        ### on this server, but if you did have multiple conf files, make
        ### sure to adjust the `/etc/init.d/redis` script (created in the
        ### next section) accordingly.
        $ sudo mkdir -p /etc/redis
        $ cp redis.conf /etc/redis/redis.conf
        
        ### Now add Redis to the default list of startup services.  Note
        ### that running Redis as a system service is not the only option.
        ### You could also run start and stop it manually.  All that
        ### matters for Feedbin is that Redis be availalbe on port 6379 by
        ### the time Feedbin launches.
        $ wget -O redis https://gist.github.com/peterc/408762/raw > /etc/init.d
        $ sed -e "s|DAEMON=/usr/bin/redis-server|DAEMON=/usr/local/bin/redis-server|g" < /etc/init.d/redis > /etc/init.d/redis.tmp
        $ mv /etc/init.d/redis.tmp /etc/init.d/redis
        $ chmod a+rx /etc/init.d/redis
        $ (cd /etc/init.d; sudo update-rc.d -f redis defaults)
        
        ### Create a `redis` user and group, which the above new init.d
        ### script will start redis-server as.
        $ adduser redis --disabled-password
        
        ### Start Redis!
        $ sudo service start redis
        
        ### Make sure it actually works:
        $ /usr/local/bin/redis-cli
        redis 127.0.0.1:6379> 
        ### Yup, that's a Redis command-line client prompt.  Type Ctrl-D to exit.

Create the PostgreSQL user
--------------------------

Set up user `feedbin` in Postgres:

        $ sudo su - postgres
        $ echo "CREATE USER feedbin WITH PASSWORD 'feedbin'; ALTER ROLE feedbin WITH SUPERUSER;" | psql
        $ exit

(You might use a different password than "`feedbin`" above, of course.)

Get the Feedbin sources
-----------------------

        $ git clone https://github.com/feedbin/feedbin.git
        $ cd feedbin

Still more dependency packages
------------------------------

Install all these packages -- various things won't work without them:

        $ apt-get install build-essential curl libreadline-dev \
                          libcurl4-gnutls-dev libpq-dev        \
                          libxml2-dev libxslt1-dev             \
                          zlib1g-dev libssl-dev git-core

Run bundle
----------

Still from within the `feedbin` source directory, do this:

        $ bundle
        ### (This may take a long time.  Go have lunch.)

Set up environment in ~/.bashrc
-------------------------------

        $ echo "export GEM_HOME='$HOME/.gems'" >> ~/.bashrc
        $ echo 'export PATH=$HOME/.gems/bin:${PATH}' >> ~/.bashrc
        
        ### Next, grab the output of `rake secret` and use it as the value
        ### of SECRET_KEY_BASE in ~/.bashrc.  But because `rake secret`
        ### sometimes prints warning output (as in the example below),
        ### do this manually instead of with a ">>" redirect.  Thus:
        $ rake secret
        [fog][WARNING] Unable to load the 'unf' gem.  Your AWS strings
        may not be properly encoded.
        33e43f9f2748<<<omitting some to save space here>>>21bdfadff4fbf4d
        ### Take the value beginning "33e43f..." and put a line like this
        ### at the end of ~/.bashrc:
        ###
        ###    export SECRET_KEY_BASE=33e43f9f2748<<<...etc...>>>
        ###
        ### Okay, continue setting other variables:
        $ echo "export DATABASE_URL=postgres://feedbin:feedbin@localhost/feedbin_development" >> ~/.bashrc
        $ echo "export POSTGRES_USERNAME=feedbin" >> ~/.bashrc
        $ exec $SHELL  ### (or log out and log back in) ###

Set up the database
-------------------

Edit `/etc/postgresql/9.3/main/pg_hba.conf` to have a line like this:

        local   all             feedbin                                 md5

(It should probably go right before the `local  all  all  peer` line.)

Then restart PostgreSQL, to make sure it gets the above change:

        $ sudo service postgres restart

Then ask feedbin to set up the rest of the database:

        $ rake db:setup

(TODO 2013-11-10: This gets an error right now due to unavailability
of hstore extension.  Working on it.)
