# Contributing

1. Install Ruby, ImageMagick, and optionally ffmpeg.
2. Run `bundle install` and `bundle exec rspec`.
3. Keep compose rendering deterministic and keep PTY execution optional.
4. Add one focused regression test for behavior changes.
5. Run `gem build shellfie.gemspec` before submitting a release-related change.

New configuration keys must be validated in Ruby and added to the matching file under `schema/`.
