
class DevEnvUtils


    def self.searchAndOpenLocalExample(path)
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

    def self.checkAndRemoveSubmodule(path)
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

    def self.checkTagIsEqualToHead(tag, path)
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
    def self.checkTagOrBranchIsEqalToHead(branchOrTag, path)
        _currentDir = Dir.pwd
        Dir.chdir(path)
        headCommitID = `git rev-parse HEAD`
        tagCommitID = `git rev-parse #{branchOrTag}`
        UI.puts "#{`pwd`}  headCommitID:#{headCommitID} \n #{branchOrTag}ComitID:#{tagCommitID}"
        Dir.chdir(_currentDir)
        return (headCommitID.length > 0 && headCommitID == tagCommitID)
    end

    def self.checkGitStatusAndPush(pod_name)
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

    def self.checkRemoteTagExist(tag)
        `git push --tags`
        ret = system("git ls-remote --exit-code origin refs/tags/#{tag}")
        return ret
    end

    def self.addGitTagAndPush(tag, pod_name)
        ret = system("git tag #{tag}")
        if ret == true
            ret = system("git push origin #{tag}")
            if ret != true
                raise "💔 #{pod_name.yellow} push tag 失败"
            end
        end
        return ret
    end

    def self.inputNeedJumpForReson(str)
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
end