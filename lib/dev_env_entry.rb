# frozen_string_literal: true

require 'cocoapods'
require 'file_processer'
require 'luna-binary-uploader'
require 'dev_env_utils'

Pod::HooksManager.register('cocoapods-dev-env', :pre_install) do |installer|
    # puts installer.instance_variables
    # forbidden submodule not cloned
    # 会引起submodule HEAD回滚，不靠谱，先注释掉
    # `
    # git submodule update --init --recursive
    # `
end

Pod::HooksManager.register('cocoapods-dev-env', :post_install) do |installer|
    # puts installer.instance_variables
end


$processedPodsState = Hash.new
$processedPodsOptions = Hash.new

$podFileContentPodNameHash = Hash.new

$devEnvUseBinaryHash = Hash.new

# for universal dependency 子库引用父文件夹中的podFile或lock文件的相对路径
$parrentPath = '../../../'


module Pod

    class DevEnv
        def self.keyword
            :dev_env # 'dev'/'beta'/'release'
        end
        def self.binary_key
            :dev_env_use_binary # true / false
        end
        UI.puts "🎉 plugin cocoapods-dev-env loaded 🎉".green
    end
    class Podfile

        class TargetDefinition
            attr_reader :binary_repo_url
            attr_reader :binary_source

            ## --- hook的入口函数 ---
            def parse_pod_dev_env(name, requirements)
                options = requirements.last
                pod_name = Specification.root_name(name)
                last_options = $processedPodsOptions[pod_name]
                $podFileContentPodNameHash[pod_name] = true

                if (last_options != nil)
                    UI.message "#{name.green} use last_options: #{last_options.to_s.green}"
                    if options != nil && options.is_a?(Hash)
                        requirements[requirements.length - 1] = last_options
                    else
                        requirements.push(last_options)
                    end 
                elsif options.is_a?(Hash)
                    use_binary = options.delete(Pod::DevEnv::binary_key)
                    dev_env = options.delete(Pod::DevEnv::keyword)

                    # 主功能，根据dev_env标记来管理使用代码的方式
                    deal_dev_env_with_options(dev_env, options, pod_name, name, requirements)

                    # 处理二进制
                    if dev_env != 'dev' 
                        binary_processer(dev_env, pod_name, use_binary, options, requirements)
                    end


                    if dev_env || use_binary 
                        $processedPodsOptions[pod_name] = options.clone
                        requirements.pop if options.empty?
                    end
                end    
            end

            ## --- 主功能函数 ---
            def deal_dev_env_with_options(dev_env, options, pod_name, name, requirements) 
                if dev_env == nil 
                    return
                end

                defaultLocalPath = "./developing_pods/#{pod_name}"
                UI.message "pod #{name.green} dev-env: #{dev_env.green}"
                isFromSubProject = false
                if dev_env == 'parent'
                    parentPodInfo = $parentPodlockDependencyHash[pod_name]
                    if parentPodInfo != nil
                        if parentPodInfo.external_source != nil
                            git = parentPodInfo.external_source[:git]
                            if git != nil
                                options[:git] = git
                            end
                            tag = parentPodInfo.external_source[:tag]
                            if tag != nil
                                options[:tag] = tag
                            end
                        elsif (parentPodInfo.podspec_repo.start_with?("http") || parentPodInfo.podspec_repo.start_with?("git"))
                            #UI.puts 'XXXXXXXXXXXXXXXX123' + parentPodInfo.inspect
                            requirements.insert(0, parentPodInfo.requirement.to_s)
                            options[:source] = parentPodInfo.podspec_repo
                        end
                    end
                    return
                elsif options[:git] == nil
                    podfilePath = $parrentPath + '/Podfile'
                    temp = `grep \\'#{pod_name}\\' #{podfilePath} | grep ':dev_env'`
                    if temp != nil && temp.length > 0
                        UI.puts temp
                        git = /(:git.*?').*?(?=')/.match(temp)[0]
                        git = git.gsub(/:git.*?'/, '')
                        branch = /(:branch.*?').*?(?=')/.match(temp)[0]
                        branch = branch.gsub(/:branch.*?'/, '')
                        tag = /(:tag.*?').*?(?=')/.match(temp)[0]
                        tag = tag.gsub(/:tag.*?'/, '')
                        path = /(:path.*?').*?(?=')/.match(temp)
                        if path != nil
                            path = path[0]
                            path = path.gsub(/:path.*?'/, '')
                        end
                        options[:git] = git
                        options[:branch] = branch
                        options[:tag] = tag
                        if path != nil
                            options[:path] = path
                        else
                            options[:path] = defaultLocalPath
                        end
                        UI.puts "#{pod_name.green}采用了父组件的配置，并修改开发状态为#{dev_env.green}"
                        isFromSubProject = true
                    end
                end
            


                git = options.delete(:git)
                branch = options.delete(:branch)
                tag = options.delete(:tag)
                path = options.delete(:path) # 执行命令用的path
                if path == nil 
                    path = defaultLocalPath
                end
                realpath = path
                if isFromSubProject
                    realpath = $parrentPath + path
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

                if dev_env == 'subtree'
                    if isFromSubProject
                        raise "💔 子项目不支持subtree"
                    end
                    if !File.directory?(path)
                        _toplevelDir = `git rev-parse --show-toplevel`
                        _currentDir = `pwd`
                        _subtreeDir = path
                        if _currentDir != _toplevelDir
                            Dir.chdir(_toplevelDir)
                            _end = path
                            if _end[0,2] == './'
                                _end = _end[1, _end.length - 1]
                            else
                                _end = '/' + _end
                            end
                            _subtreeDir = './' + _currentDir[_toplevelDir.length, _currentDir.length - _toplevelDir.length] + path
                        end
                        _cmd = "git subtree add --prefix #{_subtreeDir} #{git} #{branch} --squash"
                        UI.puts _cmd
                        system(_cmd)
                        Dir.chdir(_currentDir)
                    end
                    options[:path] = realpath
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "pod #{pod_name.green} enabled #{"subtree".green}-mode 🍺"
                elsif dev_env == 'dev'
                    # 开发模式，使用path方式引用本地的submodule git库
                    if !File.directory?(realpath)
                        UI.puts "add submodule for #{pod_name.green}".yellow
                        curProjectDir = `pwd`
                        if isFromSubProject
                            # 进入父目录，避免当前工程目录是个submodule，当在submudle中执行addsubmodule时路径会不正确
                            Dir.chdir($parrentPath)
                        end
                        _cmd = "git submodule add --force -b #{branch} #{git} #{path}"
                        UI.puts _cmd
                        system(_cmd)
                        if isFromSubProject
                            Dir.chdir(curProjectDir)
                        end
                        _currentDir = Dir.pwd
                        Dir.chdir(path)

                        curGitRemoteUrl = `git remote get-url origin`.rstrip()
                        if curGitRemoteUrl == git
                            _cmd = "git reset --hard"
                            UI.puts _cmd
                            system(_cmd)
                            _cmd = "git pull"
                            UI.puts _cmd
                            system(_cmd)
                        end
                        Dir.chdir(_currentDir)

                        # if DevEnvUtils.inputNeedJumpForReson("本地库#{pod_name} 开发模式加载完成，是否自动打开Example工程")
                        #     DevEnvUtils.searchAndOpenLocalExample(path)
                        # end
                        if !DevEnvUtils.checkTagIsEqualToHead(tag, path) && !DevEnvUtils.checkTagIsEqualToHead("#{tag}_beta", path)
                            raise "💔 #{pod_name.yellow} branch:#{branch.yellow} 与 tag:#{tag.yellow}[_beta] 内容不同步，请自行确认所用分支和tag后重新执行 pod install"
                        end
                    else
                        # if DevEnvUtils.inputNeedJumpForReson("本地库#{pod_name} 处于开发模式，是否自动打开Example工程")
                        #     DevEnvUtils.searchAndOpenLocalExample(path)
                        # end
                    end
                    options[:path] = realpath
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "pod #{pod_name.green} enabled #{"dev".green}-mode 🍺"
                elsif dev_env == 'beta'
                    # Beta模式，使用tag引用远端git库的代码
                    originTag = tag
                    tag = "#{tag}_beta"
                    if File.directory?(path)
                        # 从Dev模式刚刚切换过来，需要打tag并且push
                        UI.puts "try to release beta-version for #{pod_name.green}".yellow
                        _currentDir = Dir.pwd
                        Dir.chdir(path)
                        # 已经进入到podspec的文件夹中了
                        DevEnvUtils.checkGitStatusAndPush(pod_name) # push一下
                        ret = DevEnvUtils.checkRemoteTagExist(tag)
                        if ret == true
                            # tag已经存在，要么没改动，要么已经手动打过tag，要么是需要引用老版本tag的代码
                            if DevEnvUtils.checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.puts "#{pod_name.green} 检测到未做任何调整，或已手动打过Tag，直接引用远端库"
                            else
                                if !DevEnvUtils.inputNeedJumpForReson("#{pod_name.green} 检测到已经存在#{tag.yellow}的tag，且与当前本地节点不同，是否跳过beta发布并删除本地submodule(直接引用远端库)")
                                    raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 且与当前Commit不对应. 请确认拉到本地之后已经在podfile中手动修改tag版本号"
                                end
                            end
                        else
                            # tag不存在，
                            DevEnvUtils.changeVersionInCocoapods(pod_name, originTag)
                            DevEnvUtils.checkGitStatusAndPush(pod_name) # 再push一下
                            DevEnvUtils.addGitTagAndPush(tag, pod_name)    
                        end
                        Dir.chdir(_currentDir)
                        DevEnvUtils.checkAndRemoveSubmodule(path)
                        UI.puts "🍺🍺 #{pod_name.green} #{tag.green} release successfully!!"
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
                        _currentDir = Dir.pwd
                        Dir.chdir(path)
                        verboseParamStr = ""
                        if Config.instance.verbose
                            verboseParamStr = " --verbose"
                        end
                        ret = system("pod lib lint --skip-import-validation --fail-fast --allow-warnings#{getReposStrForLint()}#{verboseParamStr}")
                        if ret != true
                            raise "💔 #{pod_name.yellow} lint 失败"
                        end
                        DevEnvUtils.checkGitStatusAndPush(pod_name)
                        DevEnvUtils.changeVersionInCocoapods(pod_name, tag)
                        DevEnvUtils.checkGitStatusAndPush(pod_name)
                        ret = DevEnvUtils.addGitTagAndPush(tag, pod_name)
                        if ret == false
                            if DevEnvUtils.checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.puts "#{pod_name.green} 已经打过tag".yellow
                            else
                                raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 请确认已经手动修改tag版本号"
                            end
                        end
                        ## TODO:: 发布到的目标库名称需要用变量设置
                        repoAddrs = getUserRepoAddress()
                        cmd = "pod repo push #{repoAddrs} #{pod_name}.podspec --skip-import-validation --allow-warnings --use-modular-headers#{getReposStrForLint()}#{verboseParamStr}"
                        UI.puts cmd.green
                        ret = system(cmd)
                        if ret  != true
                            raise "💔 #{pod_name.yellow} 发布失败"
                        end
                        ## 到最后统一执行，判断如果当次release过
                        `pod repo update`
                        Dir.chdir(_currentDir)
                        DevEnvUtils.checkAndRemoveSubmodule(path)
                    end
                    if requirements.length < 2
                        requirements.insert(0, "#{DevEnvUtils.get_pure_version(tag)}")
                    end
                    UI.message "enabled #{"release".green}-mode for #{pod_name.green}"
                else
                    raise "💔 :dev_env 必须要设置成 dev/beta/release之一，不接受其他值"
                end
            end

            def binary_processer(dev_env, pod_name, use_binary, options, requirements)
                if use_binary && use_binary == true
                    if options[:tag] != nil
                        begin
                            version = DevEnvUtils.get_pure_version(options[:tag])
                            spec = binary_source.specification_path(pod_name, Version.new(version))
                            if spec 
                                if requirements.length < 2
                                    options.delete(:git)
                                    options.delete(:path)
                                    options.delete(:tag)
                                    options[:source] = binary_repo_url
                                    requirements.insert(0, "#{version}")
                                    UI.puts "pod '#{pod_name.green}' 使用了二进制"
                                else
                                    UI.puts "pod '#{pod_name}' :tag => #{options[:tag]} version: #{version} 对应的版本,但是已经标记版本号#{requirements}, 不知道用哪个".red
                                end
                            else
                                UI.puts "pod '#{pod_name}' :tag => #{options[:tag]} version: #{version} 没有找到: tag 对应的版本".red
                            end
                        rescue => exception
                            UI.puts "pod '#{pod_name}' :tag => #{options[:tag]} version: #{version} 没有找到: tag 对应的版本".red
                        else

                        end
                    else
                        UI.puts "pod '#{pod_name.green}使用了二进制"
                        ## TODO:: 这里不适合处理，在这里处理的时候还不知道最终的版本号，
                        ## 无法拿到准确的版本，就不能确定二进制库里是否有对应的framework
                        ## 或者在这边预处理后，在后边的reslove的过程中找不到时再拯救一下？？
                        options.delete(:git)
                        options.delete(:path)
                        options.delete(:tag)
                        options[:source] = binary_repo_url
                    end
                end
                UI.message "#{pod_name.green} :source=> #{options[:source].green} by cocoapods-dev-env" if options[:source] != nil
                UI.message "#{pod_name.yellow} options #{options}  by cocoapods-dev-env" if options[:source] != nil
                UI.message "#{pod_name.yellow} requirements #{requirements}  by cocoapods-dev-env" if options[:source] != nil
            end

            def binary_repo_url
                if @binary_repo_url == nil
                    @binary_repo_url = Luna::Binary::Common.instance.binary_repo_url #从luna-binary-uploader里获取binary_repo_url
                end
                return @binary_repo_url
            end

            def binary_source 
                if @binary_source == nil
                    @binary_source = Pod::Config.instance.sources_manager.all.detect{|item| item.url.downcase == binary_repo_url.downcase}
                end
                return @binary_source
            end

            def find_pod_repos(pod_name) #等同pod search
                sets = Pod::Config.instance.sources_manager.search_by_name(pod_name)
                if sets.count == 1
                    set = sets.first
                elsif sets.map(&:name).include?(pod_name)
                    set = sets.find { |s| s.name == pod_name }
                else
                    names = sets.map(&:name) * ', '
                    raise Informative, "More than one spec found for '#{pod_name}':\n#{names}"
                end  
                return set  
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

