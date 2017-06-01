Feedbin Installation using Docker
---------------------------------

You must have [Docker](https://www.docker.com) 1.13.0+ and [docker-compose](https://docs.docker.com/compose/install/) installed.

1. Clone Feedbin repository:

    ```
    $ git clone https://github.com/feedbin/feedbin.git
    ```

2. Build the feedbin docker image:

    ```
    $ cd feedbin
    $ docker build -t feedbin .
    ```

3. Setup the database:

    ```
    # Start postgres, redis and elasticsearch so they have time to initialize
    $ docker-compose up -d redis postgres elasticsearch
    # Wait a few seconds for the databases to be ready to receive connections
    # Setup the database
    $ docker-compose run web rake db:setup
    ```

4. Start the workers and the application:

    ```
    $ docker-compose up
    ```

You should see Feedbin at [localhost:9292](http://localhost:9292).

The postgres data is saved in the data volume **feedbin_pgdata**.
You can remove it with the following command:

    $ docker volume rm feedbin_pgdata
