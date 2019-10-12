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
                git = options.delete(:git)
                branch = options.delete(:branch)
                tag = options.delete(:tag)
                path = options.delete(:path)
                if path == nil 
                    path = "./developing_pods/#{pod_name}"
                end
                if dev_env == 'dev' 
                    # 开发模式，使用path方式引用本地的submodule git库
                    if !File.directory?(path)
                        `git submodule add -b #{branch} #{git} #{path}`
                        currentDir = Dir.pwd
                        Dir.chdir(path)
                        headCommitID = `git rev-parse HEAD`
                        tagCommitID = `git rev-parse #{tag}`
                        if headCommitID.length > 0 && headCommitID == tagCommitID
                        else
                            raise "#{pod_name} branch:#{branch} 与 tag:#{tag} 内容不同步，请自行确认所用分支和tag后重新 install"
                            return
                        end
                    end
                    options[:path] = path
                    UI.puts "####### enabled dev-mode for #{pod_name}"
                elseif dev_env == 'beta'
                    # Beta模式，使用tag引用远端git库的代码
                    if !File.directory?(path)
                        # 从Dev模式刚刚切换过来，需要打tag并且push
                        output = `git status -s`
                        puts output
                        if output.length == 0
                            output = `git status`
                            if output.include?("push")
                                ret = system("git push")
                                if ret != true
                                    raise "#{pod_name} push 失败"
                                    return
                                end
                            end
                        else
                            raise "有未提交的数据"
                            return
                        end
                        ## TODO:: 检查tag版本号与podspec里的版本号是否一致
                        ret = system("git tag #{tag}")
                        if ret == true
                            ret = system("git push origin #{tag}")
                            if ret != true
                                raise "#{pod_name} push tag 失败"
                            end
                        else
                            raise "#{pod_name} tag:#{tag} 已存在, 请确认已经手动修改tag版本号"
                            return
                        end
                        `git rm #{path}`
                    end
                    options[:git] = git
                    options[:tag] = tag
                    UI.puts "####### enabled beta-mode for #{pod_name}"
                elseif dev_env == 'release'
                    # Release模式，直接使用远端对应的版本
                    # 需要考虑从dev直接跳跃到release的情况，需要谨慎处理，给予报错或执行两次的操作
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