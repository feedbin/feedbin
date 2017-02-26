FROM ruby:2.3.1

RUN curl -sL https://deb.nodesource.com/setup_6.x |  bash - \
  && apt-get install -y nodejs postgresql-client

RUN groupadd -r feedbin && useradd -r -g feedbin feedbin

WORKDIR /app

COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock
RUN bundle install

COPY . /app/
RUN chown -R feedbin:feedbin /app

USER feedbin
