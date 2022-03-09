require 'cocoapods'
require 'dev_env_entry'

$parentPodlockDependencyHash = Hash.new
$processedParentPods = Hash.new # 从父项目里读出来的pod当次已经下载或者加载过了就不需要再做一遍
$parrentPath = '../../../'

module Pod

    module Pod
        # Dependency扩展，通过setRequirement接口暴露内部变量的set方法
        class Dependency
          def setRequirement(requirement)
            @requirement = requirement
          end
        end
    end

    # 在这个里将父Podfile的依赖信息同步到子库里
    class Resolver

        def search_for(dependency)
            UI.message "fake search_for" + dependency.inspect
            if $podFileContentPodNameHash.has_key?(dependency.root_name)
                # 双重保证已经存在在pofile里的不再重复下载覆盖成父项目的配置
                UI.message "parrent extenal source has downloaded"
            else
                parentPodInfo = $parentPodlockDependencyHash[dependency.root_name]
                if parentPodInfo != nil
                    dependency.external_source = parentPodInfo.external_source
                    dependency.setRequirement(parentPodInfo.requirement)
                    #dependency.external_source = Hash[:path => '../../ZYSDK']
                    # dependency.external_source = Hash.new
                    UI.message "fake create_set_from_sources, changeexternal:" + dependency.inspect
                    dep = dependency
                    if !$processedParentPods.has_key?(dependency.root_name) && dependency.external_source != nil
                        $processedParentPods[dependency.root_name] = true
                        # 这里有缺陷: 已经下载过的不需要再下载了，但是不下载又进不到系统里，导致最后没有使用指定的依赖
                        # 这个没用 podfile.pod(dependency.root_name, dependency.external_source)
                        # if sandbox.specification_path(dep.root_name).nil? ||
                        #     !dep.external_source[:path].nil? ||
                        #     !sandbox.pod_dir(dep.root_name).directory? ||
                        #     checkout_requires_update?(dep)
                        #     # 已经存在就不再下载
                            source = ExternalSources.from_dependency(dependency, podfile.defined_in_file, true)
                            source.fetch(sandbox)
                        # end
                    end
                end
            end

            @search[dependency] ||= begin
              additional_requirements = if locked_requirement = requirement_for_locked_pod_named(dependency.name)
                                          [locked_requirement]
                                        else
                                          Array(@podfile_requirements_by_root_name[dependency.root_name])
                                        end
      
              specifications_for_dependency(dependency, additional_requirements).freeze
            end
        end
    end

    class Podfile
        # 在这里根据默认路径读取父Podfile里的信息
        readParrentLockFile()

        module DSL
            # 在这里根据用户配置*重新*读取父Podfile里的信息
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
    end
end