require 'yaml'
require "json"

module Saas
  class Command
    class Init < Command
      self.summary = "Generate yaml&json file"
      self.description = <<-DESC
        在当前工程目录下创建saas_config.yml以及MerchantList.json文件，用于与工程进行同步.
      DESC

      def validate!
      end

      def run
        paths = Dir.glob("*.xcodeproj")
        if paths.empty?
          puts "Error: Not found .xcodeproj on current directory".red
          return
        end
        proj_name = paths.first.delete_suffix(".xcodeproj")

        config_hash = Hash.new
        config_hash["project"] = proj_name
        config_hash["info_plist_path"] = "#{proj_name}/Info.plist"
        config_hash["main_xcassets"] = "#{proj_name}.xcassets"
        config_hash["main_storyboard"] = "Launch Screen-#{proj_name}.storyboard"

        if File.exist? "saas_config.yml"
          puts "saas_config.yml alread exist".red
        else
          puts "Generate saas_config.yml File".green
          File.write("saas_config.yml", config_hash.to_yaml)
        end

        merchant_hash = {
          "flavors": [
            {
              "config_time": Time.now.to_i, #时间戳变大才会更新
              "app_merchant": proj_name, #应用Target名,唯一标识
              "bundle_id": "com.saas.xxx", #应用bundle_id
              "app_name": "XXX", #应用展示名称
              "pro_profile": "", #打包需要证书和描述文件，证书安装在机器上
              "itc_team_id": "", #用于上传tf包到appstore
              #启动页图片
              "splash_logo": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              #AppIcon桌面图标
              "launcher_icon": {
                "_40": "40.png",
                "_58": "58.png",
                "_60": "60.png",
                "_80": "80.png",
                "_87": "87.png",
                "_120": "120.png",
                "_180": "180.png",
                "_1024": "1024.png",
              },
              #关于页面图标
              "about_us_icon": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              #首页顶部logo
              "home_logo": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              #自定义业务扩展参数
              "extra": {
 #"key1": "value1",
                               #"key2": "value2"
                },
              #业务扩展图片
              "res_extra": {
 #"res_extra_1": {
                               #      "_2x": "2x.png",
                               #      "_3x": "3x.png"
                               #}
                },
            },
          ],
        }

        if File.exist? "MerchantList.json"
          puts "MerchantList.json alread exist".red
        else
          puts "Generate MerchantList.json File".green
          File.write("MerchantList.json", JSON.pretty_generate(merchant_hash))
        end
      end
    end
  end
end