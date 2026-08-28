FROM ruby:3.4.5-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends imagemagick ffmpeg fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/shellfie
COPY . .
RUN gem build shellfie.gemspec && gem install --no-document ./shellfie-*.gem

ENTRYPOINT ["shellfie"]
