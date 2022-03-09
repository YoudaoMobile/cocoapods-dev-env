require 'cocoapods'
require 'dev_env_entry'

$parentPodlockDependencyHash = Hash.new
$processedParentPods = Hash.new # 从父项目里读出来的pod当次已经下载或者加载过了就不需要再做一遍
$parrentPath = '../../../'

module Pod

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
end