#!/bin/sh

set -e

gem install rubocop rubocop-rails rubocop-rspec rubocop-graphql httparty

ruby /action/lib/index.rb
