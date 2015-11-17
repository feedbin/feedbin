Feedbin Installation on Fedora
------------------------------

#### Feedbin Dependencies

Install a bunch of dependencies:

    sudo dnf install gcc gcc-c++ git libcurl-devel libxml2-devel libxslt-devel postgresql postgresql-devel rubygems ruby-devel rubygem-bundler ImageMagick-devel opencv-devel

Get Feedbin:

    git clone https://github.com/feedbin/feedbin.git

Install Ruby dependencies:

    cd feedbin
    bundle

#### PostgreSQL Server

Make sure your locale uses UTF-8 or you'll get errors at the rake db:setup step:

    sudo nano /etc/locale.conf
    # Make sure the LANG ends with .UTF-8
    # For example, mine looks like:
    #
    #     LANG="en_US.UTF-8"

After changing this file, it's probably a good idea to open a new terminal to make sure the changes get picked up.

Install PostgreSQL:

    sudo dnf install postgresql-server postgresql-contrib
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

#### Redis Server

Install:

    sudo dnf install redis

Start the service:

    sudo systemctl start redis

    # If you want it to auto-start:
    sudo systemctl enable redis

Note: Redis doesn't seem to work on Fedora, but Feedbin works without it.

#### Run Feedbin

Run these in the `feedbin` directory:

    bundle exec foreman start

    # In a separate terminal:
    rackup

You should see Feedbin at [localhost:9292](http://localhost:9292).
