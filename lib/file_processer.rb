#!/usr/bin/ruby

$LOAD_PATH << '.'

class YDFileUtils
    def self.writeFile (filePath, buffer)
        File.open(filePath, "w") { |source_file|
            source_file.write buffer
        }
        return
    end
end

class FileProcesserInterface
    def process(filePath)
        puts filePath
    end
end

class FileProcesser < FileProcesserInterface
    def initialize(processFunc)
        @processFunc = processFunc
    end

    def process(filePath)
        fileContent = File.read(filePath)
        result = @processFunc.call(fileContent)
        File.write(filePath, result)
    end
end

class RegexFileProcesser < FileProcesserInterface

    def initialize(regex, genLineFunc)
        @regex = regex
        @genLineFunc = genLineFunc
    end

    def process(filePath)
        buffer = ""
        IO.foreach(filePath) { |line|
            current_number_regex = line =~ @regex
            if current_number_regex
                regexCatchedValue = $~
                buffer += line.gsub(@regex, @genLineFunc.call(regexCatchedValue))
            else
                buffer += line
            end
        }
        YDFileUtils.writeFile(filePath, buffer)
    end
end



class FileProcesserManager

    def initialize(files, fileProcesserList)
        @files = files
        @fileProcesserList = fileProcesserList
    end

    private def getFiles()
        mappingFiles = Dir::glob(@files)
        return mappingFiles
    end

    private def processFile(filePath)
        @fileProcesserList.each { |processer|
            processer.process(filePath)
        }
    end

    public def process()
        ocFiles = getFiles()
        puts "共发现 #{ocFiles.count} 个文件可能需要替换"
        
        @@count = 0
        ocFiles.each do |filePath|
            processFile(filePath)
        end
    end
end

##### 最简调用示例
# FileProcesserManager.new("../**/*.{m,mm}", [FileProcesserInterface.new()]).process()

#### 通过 RegexFileProcesser 处理文件
# FileProcesserManager.new("../YoudaoDict/Vendor/SwipeView/SwipeView.m", 
#     [
#         RegexFileProcesser.new(/SwipeView/, -> (regexCatchedValue) {
#             return "#{regexCatchedValue.to_s}aaa"
#         })
# ]).process()

#### 通过gsub处理文件
# FileProcesserManager.new("../YoudaoDict/Vendor/SwipeView/SwipeView.m", 
#     [
#         FileProcesser.new(-> (fileContent) {
#             fileContent.gsub(/(SwipeView)/, "aaa\\1")
#         })
# ]).process()

# FileProcesserManager.new("../YoudaoDict/Vendor/SwipeView/SwipeView.m", 
#     [
#         FileProcesser.new(-> (fileContent) {
#             fileContent.gsub(/(SwipeView)/) do |ste|
#                 "#{$1} use gsub block"
#             end
#         })
# ]).process()


#FileProcesserManager.new("../YoudaoDict/Application/UIColor+HEXStringToColor.m",
#    [
#        FileProcesser.new(-> (fileContent) {
#            fileContent.gsub(/([self commonHEXStringToColor:@")0xF73944("])/) do |ste|
#                "#{$1} use gsub block"
#            end
#        })
#]).process()
