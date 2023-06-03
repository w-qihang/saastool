module Saas
    class Command
      class Upload < Command
        self.summary = "upload testflight"
        self.description = <<-DESC
            使用fastlane进行打包上传testflight\n
            上传TF依赖itc_team_id
          DESC
        self.arguments = [
          CLAide::Argument.new("Merchants", false, true),
        ]
  
        def initialize(argv)
          @flavors = merchant_hash["flavors"]
          @proj_name = saas_config["project"]
          @info_plist_path = saas_config["info_plist_path"]
          @merchants = argv.arguments!
          super
        end
  
        def validate!
          super
          help! "You need to specify the merchants" if @merchants.empty?
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
  
          #进行appstore上传
          upload_flavor(scheme_name, bundle_id, flavor["itc_team_id"])
        end       
  
        def upload_flavor(scheme_name, bundle_id, itc_team_id)
          puts "flavor:#{scheme_name} 上传testflight......"
          raise StandardError, "error: flavor need a itc_team_id to upload app" unless itc_team_id && itc_team_id.length > 0
  
          require "fastlane"
          require 'fastlane/actions/build_app'
          require 'fastlane/actions/upload_to_testflight'
          require 'fastlane/actions/app_store_connect_api_key.rb'
          require 'fastlane/actions/changelog_from_git_commits.rb'
          require 'spaceship'
          Spaceship::ConnectAPI::App.const_set('ESSENNTIAL_INCLUDES', 'appStoreVersions')
  
          ff = Fastlane::FastFile.new
          ff.runner = Fastlane::Runner.new
          ff.platform(:ios) do
            ff.desc("上传Testflight")
            ff.lane(:upload) do
              ff.upload_to_testflight(
                skip_submission: true, 
                skip_waiting_for_build_processing: true,
                ipa: "fastlane/#{scheme_name}.ipa",
                app_identifier:bundle_id,
                team_id: itc_team_id,
              )
            end
          end
          ff.runner.execute(:upload, :ios)
        end
      end
    end
  end