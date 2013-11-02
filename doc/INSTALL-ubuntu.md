Feedbin Installation on Ubuntu 12.04
------------------------------------

### Ubuntu 12.04 Dependencies

    apt-get install -y python-software-properties
    add-apt-repository -y ppa:pitti/postgresql
    add-apt-repository ppa:brightbox/ruby-ng-experimental
    apt-get update
    apt-get install -y ruby2.0 ruby2.0-dev build-essential curl libreadline-dev libcurl4-gnutls-dev \
                       libpq-dev libxml2-dev libxslt1-dev zlib1g-dev libssl-dev \
                       postgresql-client-9.2 postgresql-contrib-9.2 git-core

    # For all-on-one-host installation
    apt-get install -y postgresql-9.2 redis-server
    sudo su - postgres
    echo "CREATE USER feedbin WITH PASSWORD 'feedbin'; \
    ALTER ROLE feedbin WITH SUPERUSER;" | psql
    exit

    # Setting up feedbin time!
    git clone https://github.com/feedbin/feedbin.git
    cd feedbin
    echo "export GEM_HOME='$HOME/.gems'" >> ~/.bashrc
    echo 'export PATH=$HOME/.gems/bin:${PATH}' >> ~/.bashrc
    echo "export SECRET_KEY_BASE=$(rake secret)" >> ~/.bashrc
    echo "export DATABASE_URL=postgres://feedbin:feedbin@localhost/feedbin_development" >> ~/.bashrc
    echo "export POSTGRES_USERNAME=feedbin" >> ~/.bashrc
    source ~/.bashrc

    gem install bundler redis
    bundle

    vim config/database.yml # Edit this file to insert the 'feedbin' postgres password

    rake db:setup

    # Preferebly run these two in two separate terminals (or a screen!)
    bundle exec foreman start &
    rackup
