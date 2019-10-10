Pod::HooksManager.register('cocoapods-dev-env', :pre_install) do |installer|
    podfile = installer.podfile
    #puts installer.instance_variables
end

Pod::HooksManager.register('cocoapods-dev-env', :post_install) do |installer|
    #puts installer.instance_variables
end


$processedPodsState = Hash.new

module Pod
    class DevEnv
        def self.keyword
            :dev_env # 'dev'/'beta'/'release'
        end
    end
class Podfile
    class TargetDefinition

        ## --- option for setting using prebuild framework ---
        def parse_pod_dev_env(name, requirements)
            options = requirements.last
            pod_name = Specification.root_name(name)
            dev_env = $processedPodsState[pod_name]
            if options.is_a?(Hash)
                if dev_env == nil
                    if options[Pod::DevEnv::keyword] != nil 
                        dev_env = options.delete(Pod::DevEnv::keyword)
                        $processedPodsState[pod_name] = dev_env
                    else
                        options.delete(Pod::DevEnv::keyword)
                        return
                    end
                end
                UI.puts "####### proccess dev-env for pod #{pod_name} env: #{dev_env}"
                if dev_env == 'dev' 
                    git = options.delete(:git)
                    branch = options.delete(:branch)
                    path = "./developing_pods/#{pod_name}"
                    if !File.directory?(path)
                        `git submodule add -b #{branch} #{git} #{path}`
                    end
                    options[:path] = path
                    UI.puts "####### enable dev-mode for #{pod_name}"
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