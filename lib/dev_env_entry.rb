# frozen_string_literal: true

require 'cocoapods'
require 'file_processer'
require 'luna-binary-uploader'

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


module Pod
    class Dependency
      def setRequirement(requirement)
        @requirement = requirement
      end
    end
end


module Pod

    class DevEnv
        def self.keyword
            :dev_env # 'dev'/'beta'/'release'
        end
        def self.binary_key
            :dev_env_use_binary # true / false
        end
        UI.message "🎉 plugin cocoapods-dev-env loaded 🎉".green
    end
    class Podfile
        module DSL
            def use_parent_lock_info!(option = true)
                case option
                when true, false
                    if !option
                        $parrentPath = ''
                        TargetDefinition.cleanParrentLockFile()
                    end
                when Hash
                    $parrentPath = option.fetch(:path)
                    TargetDefinition.readParrentLockFile()
                else
                  raise ArgumentError, "Got `#{option.inspect}`, should be a boolean or hash."
                end
            end
        end

        class TargetDefinition
            attr_reader :binary_repo_url
            attr_reader :binary_source

            def searchAndOpenLocalExample(path)
                _currentDir = Dir.pwd
                Dir.chdir(path)
                Dir.chdir("Example")
                `pod install`
                projPaths = Dir::glob("*.xcworkspace")
                if projPaths.count > 0
                    `open -a Terminal ./`
                    `open #{projPaths[0]}`
                end
                Dir.chdir(_currentDir)
            end

            def checkAndRemoveSubmodule(path)
                _currentDir = Dir.pwd
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
                Dir.chdir(_currentDir)
                `
                git submodule deinit #{path}
                rm -rf #{path}
                git rm #{path}
                `
            end

            def checkTagIsEqualToHead(tag, path)
                _currentDir = Dir.pwd
                Dir.chdir(path)
                result = `git describe --abbrev=4 HEAD`
                Dir.chdir(_currentDir)
                if result.include?(tag)
                    return true
                else
                    return checkTagOrBranchIsEqalToHead(tag, path)
                end
            end

            # 这个函数有问题有时候拿不到相同的commit id
            def checkTagOrBranchIsEqalToHead(branchOrTag, path)
                _currentDir = Dir.pwd
                Dir.chdir(path)
                headCommitID = `git rev-parse HEAD`
                tagCommitID = `git rev-parse #{branchOrTag}`
                UI.puts "#{`pwd`}  headCommitID:#{headCommitID} \n #{branchOrTag}ComitID:#{tagCommitID}"
                Dir.chdir(_currentDir)
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

            def checkRemoteTagExist(tag)
                `git push --tags`
                ret = system("git ls-remote --exit-code origin refs/tags/#{tag}")
                return ret
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
                if ARGV.include? '--silent'
                    return false
                end

                puts str.green
                puts '是(Y), 任意其他输入或直接回车跳过'.green
                input = STDIN.gets
                if input[0,1] == "Y"
                    return true
                else
                    return false
                end
            end

            def getReposStrForLint()
                if podfile.sources.size == 0
                    return ""
                end
                str = " --sources="
                podfile.sources.each do |source|
                    str += source
                    str += ","
                end
                UI.puts str
                return str
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
                UI.puts "#{"选择了发布到: ".yellow}. #{source.green}(#{index + 1})"
                return source
            end

            def changeVersionInCocoapods(name, newVersion)
                if (newVersion == nil)
                    UI.puts "💔 切换版本号的版本现在为空，无法设置版本号".yellow
                    return
                end
                newVersion = get_pure_version(newVersion)
                specName = name + ".podspec"
                FileProcesserManager.new(specName, 
                    [
                        FileProcesser.new(-> (fileContent) {
                            return fileContent.gsub(/(\.version *= *')(.*')/, "\\1" + newVersion + "'")
                        })
                ]).process()
                `git add #{specName}
                 git commit -m "Mod: 修改版本号为:#{newVersion} by cocoapods_dev_env plugin"`
            end

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
                UI.message "pod #{name.green} dev-env: #{dev_env.green}"
                if dev_env == 'parent'
                    parentPodInfo = $parentPodlockDependencyHash[pod_name]
                    if parentPodInfo != nil
                        git = parentPodInfo.external_source[:git]
                        if git != nil
                            options[:git] = git
                        end
                        tag = parentPodInfo.external_source[:tag]
                        if tag != nil
                            options[:tag] = tag
                        end
                        # dependency.setRequirement(parentPodInfo.requirement
                    end
                    return
                elsif options[:git] == nil
                    podfilePath = $parrentPath + '/Podfile'
                    temp = `grep #{pod_name} #{podfilePath} | grep ':dev_env'`
                    git = /(:git.*?').*?(?=')/.match(temp)[0]
                    git = git.gsub(/:git.*?'/, '')
                    branch = /(:branch.*?').*?(?=')/.match(temp)[0]
                    branch = branch.gsub(/:branch.*?'/, '')
                    tag = /(:tag.*?').*?(?=')/.match(temp)[0]
                    tag = tag.gsub(/:tag.*?'/, '')
                    # path = /(:path.*?').*?(?=')/.match(temp)[0]
                    # path = path.gsub(/:path.*?'/, '')
                    options[:git] = git
                    options[:branch] = branch
                    options[:tag] = tag
                    # options[:path] = path
                    #temp = temp[pre.length, temp.length - pre.length]
                    #temp = temp.gsub('beta', 'dev')
                    UI.puts "XXXXXXXXXXXX".red + git
                    #val = eval temp
                    #UI.puts = val.inspect
                end
            


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

                if dev_env == 'subtree'
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
                    options[:path] = path
                    if requirements.length >= 2
                        requirements.delete_at(0)
                    end
                    UI.message "pod #{pod_name.green} enabled #{"subtree".green}-mode 🍺"
                elsif dev_env == 'dev'
                    # 开发模式，使用path方式引用本地的submodule git库
                    if !File.directory?(path)
                        UI.puts "add submodule for #{pod_name.green}".yellow
                        _cmd = "git submodule add --force -b #{branch} #{git} #{path}"
                        UI.puts _cmd
                        system(_cmd)

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

                        # if inputNeedJumpForReson("本地库#{pod_name} 开发模式加载完成，是否自动打开Example工程")
                        #     searchAndOpenLocalExample(path)
                        # end
                        if !checkTagIsEqualToHead(tag, path) && !checkTagIsEqualToHead("#{tag}_beta", path)
                            raise "💔 #{pod_name.yellow} branch:#{branch.yellow} 与 tag:#{tag.yellow}[_beta] 内容不同步，请自行确认所用分支和tag后重新执行 pod install"
                        end
                    else
                        # if inputNeedJumpForReson("本地库#{pod_name} 处于开发模式，是否自动打开Example工程")
                        #     searchAndOpenLocalExample(path)
                        # end
                    end
                    options[:path] = path
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
                        checkGitStatusAndPush(pod_name) # push一下
                        ret = checkRemoteTagExist(tag)
                        if ret == true
                            # tag已经存在，要么没改动，要么已经手动打过tag，要么是需要引用老版本tag的代码
                            if checkTagOrBranchIsEqalToHead(tag, "./")
                                UI.puts "#{pod_name.green} 检测到未做任何调整，或已手动打过Tag，直接引用远端库"
                            else
                                if !inputNeedJumpForReson("#{pod_name.green} 检测到已经存在#{tag.yellow}的tag，且与当前本地节点不同，是否跳过beta发布并删除本地submodule(直接引用远端库)")
                                    raise "💔 #{pod_name.yellow} tag:#{tag.yellow} 已存在, 且与当前Commit不对应. 请确认拉到本地之后已经在podfile中手动修改tag版本号"
                                end
                            end
                        else
                            # tag不存在，
                            changeVersionInCocoapods(pod_name, originTag)
                            checkGitStatusAndPush(pod_name) # 再push一下
                            addGitTagAndPush(tag, pod_name)    
                        end
                        Dir.chdir(_currentDir)
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
                        checkGitStatusAndPush(pod_name)
                        changeVersionInCocoapods(pod_name, tag)
                        checkGitStatusAndPush(pod_name)
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
                        cmd = "pod repo push #{repoAddrs} #{pod_name}.podspec --skip-import-validation --allow-warnings --use-modular-headers#{getReposStrForLint()}#{verboseParamStr}"
                        UI.puts cmd.green
                        ret = system(cmd)
                        if ret  != true
                            raise "💔 #{pod_name.yellow} 发布失败"
                        end
                        ## 到最后统一执行，判断如果当次release过
                        `pod repo update`
                        Dir.chdir(_currentDir)
                        checkAndRemoveSubmodule(path)
                    end
                    if requirements.length < 2
                        requirements.insert(0, "#{get_pure_version(tag)}")
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
                            version = get_pure_version(options[:tag])
                            spec = binary_source.specification_path(pod_name, Version.new(version))
                            if spec 
                                if requirements.length < 2
                                    options.delete(:git)
                                    options.delete(:path)
                                    options.delete(:tag)
                                    options[:source] = binary_repo_url
                                    requirements.insert(0, "#{version}")
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
                        options.delete(:git)
                        options.delete(:path)
                        options.delete(:tag)
                        options[:source] = binary_repo_url
                    end

                else
                    if options[:source] == nil
                        begin
                            # 二进制开启后再关闭，由于版本号一致，缓存不会自动切回原来的source，这里是处理这个问题
                            # 目前看拖慢速度，可能需要想办法去掉
                            sources = find_pod_repos(pod_name).sources.select{|item| item.url.downcase != binary_repo_url.downcase } if options.empty?
                            if sources != nil
                                if sources.length >= 2
                                    UI.puts "#{pod_name.green} 有多个source #{sources}".yellow
                                    source_url = sources.detect{|item| item.url.downcase != Pod::TrunkSource::TRUNK_REPO_URL.downcase && item.url.downcase != "https://github.com/CocoaPods/Specs.git".downcase}.url
                                else
                                    source_url = sources.first.url
                                end
                            end
                            options[:source] = source_url if source_url != nil
                        rescue => exception
                            UI.puts "#{pod_name} exception:#{exception}".red
                        else

                        end
                    end
                end
                UI.puts "#{pod_name.green} :source=> #{options[:source].green} by cocoapods-dev-env" if options[:source] != nil
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

            def get_pure_version(version) 
                return version.split.last.scan(/\d+/).join('.') 
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

            def self.cleanParrentLockFile()
                $parentPodlockDependencyHash = Hash.new
            end

            # 类方法
            def self.readParrentLockFile()
                # 获取路径（之后外边直接配置)
                localPath = Pathname.new(Dir.pwd + "/" + $parrentPath)
                lockPath ||= localPath + "Podfile.lock"
                # 读取lockfile
                _lockfile = Pod::Lockfile.from_file(lockPath)
                if _lockfile == nil
                    UI.message "dev_env, 读取父库的lockfile找不到对应路径的lock文件:" + lockPath.inspect
                    return
                end
                # 读取lockfile中的依赖信息，用于之后提取使用，其中数据为 Pod::Dependency类型
                localPodsMaps = Hash.new()
                localpods = _lockfile.dependencies
                localpods.each do |dep|
                    # 数据为 Pod::Dependency类型
                    if (dep.external_source == nil && dep.requirement == nil) || localPodsMaps.has_key?(dep.root_name)
                        next
                    end
                    if dep.external_source == nil && dep.requirement.to_s == '>= 0'
                        # dependence里可能没有版本信息（很奇怪，从version里单独取一下，写死版本限制）
                        version = _lockfile.version(dep.root_name)
                        dep.setRequirement(Requirement.new(version))
                    end
                    if dep.local?
                        dep.external_source[:path] = $parrentPath + dep.external_source[:path]
                    end
                    # 测试代码 UI.puts "测试获取父项目podlock里的pod依赖列表: " + dep.inspect
                    localPodsMaps[dep.root_name] = dep
                end
                $parentPodlockDependencyHash = localPodsMaps
                # 读取 示例: ydASRInfo = localPodsMaps['YDASR']
                # UI.puts ydASRInfo.inspect
                # UI.puts "YDASR path:\n" + ydASRInfo.external_source[:path]
            end

            readParrentLockFile()
        end
    end
end
