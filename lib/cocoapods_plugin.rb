Pod::HooksManager.register('cocoapods-dev-env', :pre_install) do |installer|
    podfile = installer.podfile
    puts "XXXXXXXXXXXXXXXXXXX"
    puts installer.instance_variables


end

Pod::HooksManager.register('cocoapods-dev-env', :post_install) do |installer|
    puts "BBBBBBBBBBBBBBBBBBBB"
    puts installer.instance_variables
end

module Pod
    class DevEnv
        def self.keyword
            :is_dev
        end
    end
class Podfile
    class TargetDefinition

      ## --- option for setting using prebuild framework ---
      def parse_pod_dev_env(name, requirements)
          options = requirements.last
          pod_name = Specification.root_name(name)
          UI.puts "!!!!!!!####### proccess for dev-env #{pod_name} :\n #{options}"
            if options.is_a?(Hash) && options[Pod::DevEnv::keyword] != nil 
                is_dev = options.delete(Pod::DevEnv::keyword)
                if is_dev
                    git = options.delete(:git)
                    branch = options.delete(:branch)
                    path = "./developing_pods/#{pod_name}"
                    if !File.directory?(path)
                        `git submodule add -b #{branch} #{git} #{path}`
                    end
                    options[:path] = path
                    UI.puts "!!!!!!!####### enable dev-mode"
                else
                    # 移除有可能误删往提交的内容，需要谨慎处理
                    #`git rm #{path}`
                end
                requirements.pop if options.empty?
            end
      end

      # ---- patch method ----
        # We want modify `store_pod` method, but it's hard to insert a line in the 
        # implementation. So we patch a method called in `store_pod`.
        old_method = instance_method(:parse_inhibit_warnings)

        define_method(:parse_inhibit_warnings) do |name, requirements|
            parse_pod_dev_env(name, requirements)
            old_method.bind(self).(name, requirements)
        end
    end
end
end