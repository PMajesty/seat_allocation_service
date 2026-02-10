source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.0"

gem "rails", "~> 8.0.0"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

gem "bcrypt"
gem "jwt"
gem "redis"
gem "connection_pool", "~> 2.4.1"

gem "sprockets-rails"
gem "dartsass-rails"
gem "rack-attack"
gem "dotenv-rails", groups: %i[development test]
gem "importmap-rails"

gem "whenever"

gem "elasticsearch-model"
gem "elasticsearch-rails"
gem "kaminari"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "rspec-rails"
  gem "faker"
  gem "brakeman", require: false
  gem "rubocop", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
  gem "foreman"
end

gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]
