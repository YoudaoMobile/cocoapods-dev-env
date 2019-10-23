Pod::HooksManager.register('cocoapods-dev-env', :pre_install) do |installer|
    podfile = installer.podfile
    #puts installer.instance_variables
end

Pod::HooksManager.register('cocoapods-dev-env', :post_install) do |installer|
    #puts installer.instance_variables
end


$processedPodsState = Hash.new
$processedPodsOptions = Hash.new

module Pod
    class DevEnv
        def self.keyword
            :dev_env # 'dev'/'beta'/'release'
        end
        puts "🎉 plugin cocoapods-dev-env loaded 🎉".green
    end
class Podfile
    class TargetDefinition

        def checkAndRemoveSubmodule(path)
            currentDir = Dir.pwd
            Dir.chdir(path)
            output = `git status -s`
            puts output
            if output.length == 0
                output = `git status`
                if output.include?("push")
                    raise "submodule #{path} 移除失败，有推送的修改"
                end
            else
                raise "submodule #{path} 移除失败，有未提交的修改"
            end
            Dir.chdir(currentDir)
            `
            git submodule deinit #{path}
            rm -rf #{path}
            git rm #{path}
            `
        end

        def checkTagIsEqualToHead(tag, path)
            currentDir = Dir.pwd
            Dir.chdir(path)
            result = `git describe --abbrev=4 HEAD`
            Dir.chdir(currentDir)
            return result.include?(tag)
        end

# 这个函数有问题有时候拿不到相同的commit id
        def checkTagOrBranchIsEqalToHead(branchOrTag, path)
            currentDir = Dir.pwd
            Dir.chdir(path)
            headCommitID = `git rev-parse HEAD`
            tagCommitID = `git rev-parse #{branchOrTag}`
            UI.puts "#{`pwd`}  headCommitID:#{headCommitID} \n #{branchOrTag}ComitID:#{tagCommitID}"
            Dir.chdir(currentDir)
            return (headCommitID.length > 0 && headCommitID == tagCommitID)
        end

        ## --- option for setting using prebuild framework ---
        def parse_pod_dev_env(name, requirements)
            options = requirements.last
            pod_name = Specification.root_name(name)
            last_options = $processedPodsOptions[pod_name]
            if (last_options != nil)
                UI.message "#{name.green} use last_options: #{last_options.to_s.green}"
                if options != nil && options.is_a?(Hash)
                    requirements[requirements.length - 1] = last_options
                else
                    requirements.push(last_options)
                end 
                
                return
            end
            if options.is_a?(Hash)
                dev_env = options.delete(Pod::DevEnv::keyword)
                if dev_env == nil 
                    return
                end
                UI.message "pod #{name.green} dev-env: #{dev_env.green}"
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
                        UI.puts "add submodule for #{pod_name.green}".yellow
                        `git submodule add --force -b #{branch} #{git} #{path}`
                        
                        if !checkTagIsEqualToHead(tag, path) && !checkTagIsEqualToHead("#{tag}_beta", path)
                            raise "💔 #{pod_name.yellow} branch:#{branch.yellow} 与 tag:#{tag.yellow}[_beta] 内容不同步，请自行确认所用分支和tag后重新执行 pod install"
                        end
                    end
                    options[:path] = path
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "enabled #{"dev".green}-mode for #{pod_name.green}"
                elsif dev_env == 'beta'
                    # Beta模式，使用tag引用远端git库的代码
                    tag = "#{tag}_beta"
                    if File.directory?(path)
                        # 从Dev模式刚刚切换过来，需要打tag并且push
                        UI.puts "gen beta env for #{pod_name.green}".yellow
                        if tag == nil || tag.length == 0 
                            raise "💔 #{pod_name.yellow} 未定义tag"
                        end
                        currentDir = Dir.pwd
                        Dir.chdir(path)
                        output = `git status -s`
                        puts output
                        if output.length == 0
                            output = `git status`
                            if output.include?("push")
                                ret = system("git push")
                                if ret != true
                                    raise "💔 #{pod_name.yellow} push 失败"
                                end
                            end
                        else
                            raise "有未提交的数据"
                        end
                        ## TODO:: 检查tag版本号与podspec里的版本号是否一致
                        ret = system("git tag #{tag}")
                        if ret == true
                            ret = system("git push origin #{tag}")
                            if ret != true
                                raise "💔 #{pod_name.yellow} push tag 失败"
                            end
                        else
                            if checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.message "#{pod_name.green} 没做任何调整，切换回beta"
                            else
                                raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 请确认已经手动修改tag版本号"
                            end
                        end
                        Dir.chdir(currentDir)
                        checkAndRemoveSubmodule(path)
                    end
                    options[:git] = git
                    options[:tag] = tag
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "enabled #{"beta".green}-mode for #{pod_name.green}"
                elsif dev_env == 'release'
                    # Release模式，直接使用远端对应的版本
                    if File.directory?(path)
                        if tag == nil || tag.length == 0 
                            raise "💔 #{pod_name.yellow} 未定义tag"
                        end
                        currentDir = Dir.pwd
                        Dir.chdir(path)
                        
                        Dir.chdir(currentDir)
                        checkAndRemoveSubmodule(path)
                    end
                    UI.message "enabled #{"release".green}-mode for #{pod_name.green}"
                else
                    raise "💔 :dev_env 必须要设置成 dev/beta/release之一，不接受其他值"
                end
                $processedPodsOptions[pod_name] = options
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
