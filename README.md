# Cocoapods Plugin: cocoapods-dev-env

cocoapods-dev-env is a useful plugin for cocoapods to manage your self-developing pods.

When we have too many pod to developing, maybe you only care about one or two pods in local, this plugin may be can help you.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cocoapods-dev-env'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cocoapods-dev-env

## Usage

In your podfile
```ruby
plugin 'cocoapods-dev-env'

pod 'SomePod', :git => 'xxxxxx', :branch => 'master', :tag => '0.0.2.2', :dev_env => 'dev'
```
We see a addtional key "dev_env" in defineation. And you must put "git", "branch", "tag" for the plugin.

1. When you define "dev_env" to "dev", and run ```pod install``` .  
We will add a ```git submodule``` linked to your pod git repo to local.  
And check if the ```HEAD``` commit id of the branch is same to ```tag```commit id.

2. When you define "dev_env" to "beta", and run ```pod install``` .  
We will use the ```tag```: "tag_beta", e.g.: "0.0.2.2_beta"  
When the local git submodule is exist, whe aslo try to check and add tag "tag_beta" on it and push to the origin.  
Finally the state clean submodule will be removed automatically.

3. When you define "dev_env" to "release", and run ```pod install``` . 
We want to use the release version in cocoapods repo. And do many check for state, and help you to release the not released pod.  


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/YoudaoMobile/cocoapods-dev-env. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

### prepare
install gem bundler:  
    
    gem install bundler

create Gemfile:
    
    bundler init

edit GemFile for local path, e.g.:

    gem 'cocoapods'
    gem 'cocoapods-dev-env', :path => '../cocoapods-dev-env'

### debug and package
1. How to develop: put gem in your project and exec `bundle exec pod install`
2. How to packagae: `rake build` 
3. How to release: `rake release` or `gem push ./pkg/cocoapods-dev-env-0.2.2.gem` 


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Cocoapods::Dev::Env project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/YoudaoMobile/cocoapods-dev-env/blob/master/CODE_OF_CONDUCT.md).
