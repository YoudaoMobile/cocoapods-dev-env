Pod::HooksManager.register('cocoapods-dev-env', :pre_install) do |installer|
    podfile = installer.podfile
    #puts installer.instance_variables
    # forbidden submodule not cloned
    # 会引起submodule HEAD回滚，不靠谱，先注释掉
    # `
    # git submodule update --init --recursive
    # `
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

        def searchAndOpenLocalExample(path)
            currentDir = Dir.pwd
            Dir.chdir(path)
            Dir.chdir("Example")
            `pod install`
            projPaths = Dir::glob("*.xcworkspace")
            if projPaths.count > 0
                `open -a Terminal ./`
                `open #{projPaths[0]}`
            end
            Dir.chdir(currentDir)
        end

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
            if result.include?(tag)
                return true
            else
                return checkTagOrBranchIsEqalToHead(tag, path)
            end
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

        def checkGitStatusAndPush(pod_name)
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
                raise "💔 #{pod_name.yellow} 有未提交的数据"
            end
        end

        def addGitTagAndPush(tag, pod_name)
            ret = system("git tag #{tag}")
            if ret == true
                ret = system("git push origin #{tag}")
                if ret != true
                    raise "💔 #{pod_name.yellow} push tag 失败"
                end
            end
            return ret
        end

        def inputNeedJumpForReson(str)
            puts str.green
            puts '是(Y), 任意其他输入或直接回车跳过'.green
            input = STDIN.gets
            if input[0,1] == "Y"
                return true
            else
                return false
            end
        end

        def getUserRepoAddress()
            if podfile.sources.size == 0
                raise "💔 发布release必须配置仓库的地址, e.g.: source 'https://github.com/CocoaPods/Specs.git'"
            end
            index = nil
            begin
                UI.puts  "\n\n⌨️  请输入要发布到的cocoapods仓库序号, 按回车确认: ".yellow
                num = 1
                podfile.sources.each do |source|
                    UI.puts "#{num.to_s.yellow}. #{source.green}"
                    num += 1
                end
                index = STDIN.gets.to_i - 1
            end until (index >= 0 && index < podfile.sources.size)
            source = podfile.sources[index]
            return source
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
                if git == nil || git.length == 0 
                    raise "💔 #{pod_name.yellow} 未定义:git => 'xxx'库地址"
                end
                if branch == nil || branch.length == 0 
                    raise "💔 #{pod_name.yellow} 未定义:branch => 'xxx'"
                end
                if tag == nil || tag.length == 0 
                    raise "💔 #{pod_name.yellow} 未定义:tag => 'xxx', tag 将会作为 dev模式下载最新代码检查的依据，beta模式引用的tag 以及 release模式引用的版本号"
                end
                if dev_env == 'dev' 
                    # 开发模式，使用path方式引用本地的submodule git库
                    if !File.directory?(path)
                        UI.puts "add submodule for #{pod_name.green}".yellow
                        # TODO 这个命令要想办法展示实际报错信息
                        `git submodule add --force -b #{branch} #{git} #{path}`
                        if inputNeedJumpForReson("本地库#{pod_name} 开发模式加载完成，是否自动打开Example工程")
                            searchAndOpenLocalExample(path)
                        end
                        if !checkTagIsEqualToHead(tag, path) && !checkTagIsEqualToHead("#{tag}_beta", path)
                            raise "💔 #{pod_name.yellow} branch:#{branch.yellow} 与 tag:#{tag.yellow}[_beta] 内容不同步，请自行确认所用分支和tag后重新执行 pod install"
                        end
                    else
                        if inputNeedJumpForReson("本地库#{pod_name} 处于开发模式，是否自动打开Example工程")
                            searchAndOpenLocalExample(path)
                        end
                    end
                    options[:path] = path
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "pod #{pod_name.green} enabled #{"dev".green}-mode 🍺"
                elsif dev_env == 'beta'
                    # Beta模式，使用tag引用远端git库的代码
                    tag = "#{tag}_beta"
                    if File.directory?(path)
                        # 从Dev模式刚刚切换过来，需要打tag并且push
                        UI.puts "release beta-version for #{pod_name.green}".yellow
                        currentDir = Dir.pwd
                        Dir.chdir(path)
                        checkGitStatusAndPush(pod_name)
                        ## TODO:: 检查tag版本号与podspec里的版本号是否一致
                        ret = addGitTagAndPush(tag, pod_name)
                        if ret != true
                            if checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.puts "#{pod_name.green} 没做任何调整，切换回beta"
                            else
                                if !inputNeedJumpForReson("是否跳过beta发布并删除本地submodule(直接引用远端库)")
                                    raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 请确认已经手动修改tag版本号"
                                end
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
                        UI.puts "release release-version for #{pod_name.green}".yellow
                        currentDir = Dir.pwd
                        Dir.chdir(path)
                        ret = system("pod lib lint --allow-warnings")
                        if ret != true
                            raise "💔 #{pod_name.yellow} lint 失败"
                        end
                        checkGitStatusAndPush(pod_name)
                        ## TODO:: 检查tag版本号与podspec里的版本号是否一致
                        ret = addGitTagAndPush(tag, pod_name)
                        if ret == false
                            if checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.puts "#{pod_name.green} 已经打过tag".yellow
                            else
                                raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 请确认已经手动修改tag版本号"
                            end
                        end
                        ## TODO:: 发布到的目标库名称需要用变量设置
                        repoAddrs = getUserRepoAddress()
                        cmd = "pod repo push #{repoAddrs} #{pod_name}.podspec --allow-warnings"
                        ret = system(cmd)
                        if ret  != true
                            raise "💔 #{pod_name.yellow} 发布失败"
                        end
                        ## 到最后统一执行，判断如果当次release过
                        `pod repo update`
                        Dir.chdir(currentDir)
                        checkAndRemoveSubmodule(path)
                    end
                    if requirements.length < 2
                        requirements.insert(0, "#{tag}")
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
