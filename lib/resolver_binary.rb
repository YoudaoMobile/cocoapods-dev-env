require 'cocoapods'


module Pod
  class Resolver
    old_resolver_specs_by_target = instance_method(:resolver_specs_by_target)
    define_method(:resolver_specs_by_target) do
        specs_by_target = old_resolver_specs_by_target.bind(self).call

        sources_manager = Config.instance.sources_manager
        use_source_pods = podfile.use_source_pods

        missing_binary_specs = []
        specs_by_target.each do |target, rspecs|
            # use_binaries 并且 use_source_pods 不包含  本地可过滤
            use_binary_rspecs = ["SDWebImage"]
            
        #   # Parallel.map(rspecs, in_threads: 8) do |rspec|
        #   specs_by_target[target] = rspecs.map do |rspec|
        #     # 采用二进制依赖并且不为开发组件
        #     use_binary = use_binary_rspecs.include?(rspec)
        #     source = use_binary ? sources_manager.binary_source : sources_manager.code_source

        #     spec_version = rspec.spec.version
        #     UI.message 'cocoapods-imy-bin 插件'
        #     UI.message "- 开始处理 #{rspec.spec.name} #{spec_version} 组件."

        #     begin
        #       # 从新 source 中获取 spec,在bin archive中会异常，因为找不到
        #       specification = source.specification(rspec.root.name, spec_version)
        #       UI.message "#{rspec.root.name} #{spec_version} \r\n specification =#{specification} "
        #       # 组件是 subspec
        #       if rspec.spec.subspec?
        #         specification = specification.subspec_by_name(rspec.name, false, true)
        #       end
        #       # 这里可能出现分析依赖的 source 和切换后的 source 对应 specification 的 subspec 对应不上
        #       # 造成 subspec_by_name 返回 nil，这个是正常现象
        #       next unless specification

        #       used_by_only = if Pod.match_version?('~> 1.7')
        #                        rspec.used_by_non_library_targets_only
        #                      else
        #                        rspec.used_by_tests_only
        #                      end
        #       # used_by_only = rspec.respond_to?(:used_by_tests_only) ? rspec.used_by_tests_only : rspec.used_by_non_library_targets_only
        #       # 组装新的 rspec ，替换原 rspec
        #       if use_binary
        #         rspec = if Pod.match_version?('~> 1.4.0')
        #                   ResolverSpecification.new(specification, used_by_only)
        #                 else
        #                   ResolverSpecification.new(specification, used_by_only, source)
        #                 end
        #         UI.message "组装新的 rspec ，替换原 rspec #{rspec.root.name} #{spec_version} \r\n specification =#{specification} \r\n #{rspec} "

        #       end

        #     rescue Pod::StandardError => e
        #       # 没有从新的 source 找到对应版本组件，直接返回原 rspec

        #       # missing_binary_specs << rspec.spec if use_binary
        #       missing_binary_specs << rspec.spec
        #       rspec
        #     end

        #     rspec
        #   end.compact
        end

        # if missing_binary_specs.any?
        #   missing_binary_specs.uniq.each do |spec|
        #     UI.message "【#{spec.name} | #{spec.version}】组件无对应二进制版本 , 将采用源码依赖."
        #   end
        #   Pod::Command::Bin::Archive.missing_binary_specs(missing_binary_specs)

        #   #缓存没有二进制组件到spec文件，local_psec_dir 目录
        #   sources_sepc = []
        #   des_dir = CBin::Config::Builder.instance.local_psec_dir
        #   FileUtils.rm_f(des_dir) if File.exist?des_dir
        #   Dir.mkdir des_dir unless File.exist?des_dir
        #   missing_binary_specs.uniq.each do |spec|
        #     next if spec.name.include?('/')

        #     spec_git_res = false
        #     CBin::Config::Builder.instance.ignore_git_list.each do |ignore_git|
        #       spec_git_res = spec.source[:git] && spec.source[:git].include?(ignore_git)
        #       break if spec_git_res
        #     end
        #     next if spec_git_res

        #     #获取没有制作二进制版本的spec集合
        #     sources_sepc << spec
        #     unless spec.defined_in_file.nil?
        #       FileUtils.cp("#{spec.defined_in_file}", "#{des_dir}")
        #     end
        #   end
        # end

        specs_by_target
      end
    end
end