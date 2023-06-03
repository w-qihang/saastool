module Saas
    class Command
      class Build < Command
        self.summary = "build"
        self.description = <<-DESC
            使用fastlane进行构建打包\n
            打包依赖bundle_id,pro_profile,team_id
          DESC
        self.arguments = [
          CLAide::Argument.new("Merchants", false, true),
        ]
  
        def self.options
          [
            ["--version", "指定要打包上传的版本号"],
            ["--platform=[appstore|test]", "指定上传包的平台，默认appstore，且目前只支持上传TF包到App Store"],
          ].concat(super)
        end
  
        def initialize(argv)
          @flavors = merchant_hash["flavors"]
          @proj_name = saas_config["project"]
          @info_plist_path = saas_config["info_plist_path"]  
          @merchants = argv.arguments!
          @version = argv.option("version")
          @platform = argv.option("platform", "appstore")  
          super
        end
  
        def validate!
          super
          help! "You need to specify the merchants" if @merchants.empty?
          help! "You need to specify the version." if @version.nil?
          help! "Specify the Info.plist path in saas_config !!!" if @info_plist_path.nil?
        end
  
        def run
          @merchants.each do |merchant|
            do_flavor @flavors.find { |flavor| flavor["app_merchant"] == merchant }
          end
        end
  
        def do_flavor(flavor)
          raise StandardError, "error: no flavor,check parameters" unless flavor.is_a?(Hash)
  
          scheme_name = flavor["app_merchant"]
          bundle_id = flavor["bundle_id"]
          raise StandardError, "error: flavor need a scheme_name" unless scheme_name && scheme_name.length > 0
          raise StandardError, "error: flavor need a bundle_id" unless bundle_id && bundle_id.length > 0
  
          #进行打包
          build_flavor(scheme_name, bundle_id, flavor["pro_profile"], flavor["team_id"])
        end       
  
        def build_flavor(scheme_name, bundle_id, pro_profile, team_id)
          puts "flavor:#{scheme_name} 构建打包中......"
          raise StandardError, "error: flavor need a pro_profile to build app" unless pro_profile && pro_profile.length > 0
  
          # 更新代码库
          if system("pod update --no-repo-update")
            project = Xcodeproj::Project.open("#{@proj_name}.xcodeproj")
            project.targets.each do |target|
              if target.platform_name == :ios && target.name == scheme_name
                target.build_configurations.map do |item|
                  if item.name == "Release"
                    item.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = pro_profile if pro_profile && pro_profile.length>0
                    item.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id if bundle_id && bundle_id.length>0
                    item.build_settings["DEVELOPMENT_TEAM"] = team_id if team_id && team_id.length>0
                  end
                end
              end
            end
            project.save
  
            # 重置版本号
            update_version_build(@version, creat_new_build_number())
            FileUtils.mkdir("fastlane") unless File.directory?("fastlane")
  
            require "fastlane"
            require 'fastlane/actions/build_app'
            require 'fastlane/actions/get_provisioning_profile.rb'
            require 'fastlane/actions/sync_code_signing.rb'
  
            ff = Fastlane::FastFile.new
            ff.runner = Fastlane::Runner.new
            ff.platform(:ios) do
              ff.desc("fastlane打包")
              ff.lane(:build) do
                ff.build_app(
                  workspace: "#{@proj_name}.xcworkspace", 
                  scheme: scheme_name, 
                  silent: true, 
                  suppress_xcode_output: true, 
                  buildlog_path: "fastlane/logs", 
                  output_directory: "fastlane", 
                  export_options: { 
                    manageAppVersionAndBuildNumber: false,
                    provisioningProfiles: { 
                      bundle_id => pro_profile,
                    }
                  }
                )
              end
            end
            ff.runner.execute(:build, :ios)
          end
        end 
  
        def update_version_build(app_version, app_build)
          puts "更新工程plist版本号:version=#{app_version},build=#{app_build}......".green
          info_plist = Xcodeproj::Plist.read_from_path(@info_plist_path)
          raise StandardError, "Not found plist in path:#{@info_plist_path}!!!" if info_plist.nil?
  
          info_plist["CFBundleShortVersionString"] = app_version
          info_plist["CFBundleVersion"] = app_build
          Xcodeproj::Plist.write_to_path(info_plist, @info_plist_path)
        end
  
        # 获取工程build_number,并计算新值
        def creat_new_build_number()
          currentTime = Time.new.strftime("%m%d%H%M%S")
          return "#{@version}.#{currentTime}"
        end
      end
    end
  end