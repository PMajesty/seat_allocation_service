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

gem "sidekiq", "< 8"
gem "connection_pool", "~> 3.0.2"

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
end

gem "tzinfo-data", platforms: %i[mingw mswin x64_mingw jruby]
