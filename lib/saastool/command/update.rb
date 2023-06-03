require "xcodeproj"
require "open-uri"
require "rexml/document"

module Saas
  class Command
    class Update < Command
      self.summary = "Sync the Xcode Project file with json file"
      self.description = <<-DESC
          将本地MerchantList.json与工程文件进行同步.\n
          可指定merchant，默认全部更新\n
          每个merchant对应xcode工程里相应的target以及图片资源.\n
          选择不同的scheme打包不同的马甲包.
        DESC

      self.arguments = [
        CLAide::Argument.new("Merchants", false, true),
      ]

      def initialize(argv)
        super
        @flavors = merchant_hash["flavors"]
        @proj_name = saas_config["project"]
        @project = Xcodeproj::Project.open("#{@proj_name}.xcodeproj")
        @project.targets.each do |target|
          @main_target = target if target.platform_name == :ios && target.name == @proj_name
        end
        @info_plist_path = saas_config["info_plist_path"]
        @main_xcassets = saas_config["main_xcassets"]
        @main_storyboard = saas_config["main_storyboard"]
  
        @merchants = argv.arguments!
        @env_keys = []
      end

      def validate!
        super
        help! "Specify the Info.plist path in saas_config !!!" if @info_plist_path.nil?
        help! "Specify the main xcassets in saas_config !!!" if @main_xcassets.nil?
        help! "Specify the main storyboard in saas_config !!!" if @main_storyboard.nil?
        help! "Not found main target:#{@proj_name} in project." if @main_target.nil?
      end

      def run
        @flavors.each do |flavor|
          if !flavor.is_a?(Hash)
            puts "error: no flavor".red
            next
          end

          app_merchant = flavor["app_merchant"]
          if app_merchant.nil? || app_merchant.length <= 0
            puts "error: flavor need a app_merchant".red
            next
          end

          if !@merchants.empty? && !@merchants.include?(app_merchant)
            next
          end

          puts "\nflavor:#{app_merchant} 同步配置Target中..."
          src_target = @project.targets.find { |item| item.to_s == app_merchant }
          src_target = self.create_new_flavor(app_merchant) unless src_target
          if !src_target
            puts "Initialize PBXNativeTarget Failed ".red
            next
          end

          self.config_target(flavor, src_target)
          # update images
          src_resources_build_phase = src_target.build_phases.find { |x| x.instance_of? Xcodeproj::Project::Object::PBXResourcesBuildPhase }
          xcassets_path = src_resources_build_phase.files.find { |x| x.display_name == "#{app_merchant}.xcassets" }.file_ref.real_path.to_s
          self.update_images(flavor, xcassets_path)
        end

        # 刪除工程中多余的flavor
        if @merchants.empty?
          @project.targets.each do |target|
            next if @main_target.to_s == target.to_s
            next if @flavors.map { |flavor| flavor["app_merchant"] }.include?(target.to_s)
            is_remove = true
            target.build_configurations.each do |config|
              # config_time 表示target由工具生成
              if config.build_settings["#{@proj_name.upcase}_CONFIG_TIME"].nil?
                is_remove = false
              end
            end
            self.remove_flavor(target.to_s) if is_remove
          end
        end

        self.config_plist
        #self.save_proj_json
        puts "\n===============Sync the Xcode Project file Finished !!!===============".green
        puts "Project targets maybe changed, makesure it is got automatically in Podfile!!!!!!".yellow
        system("pod install")
      end

      def create_new_flavor(target_name)
        default_resources_build_phase = @main_target.build_phases.find { |x| x.instance_of? Xcodeproj::Project::Object::PBXResourcesBuildPhase }
        default_xcassets_file = default_resources_build_phase.files.find { |x| x.display_name == @main_xcassets }
        default_storyboard_file = default_resources_build_phase.files.find { |x| x.display_name == @main_storyboard }
        if !default_xcassets_file
          puts "error: default xcassets do not exist, please specify the correct xcassets in the saas_config".red
          return nil
        end
        if !default_storyboard_file
          puts "error: default storyboard do not exist, please specify the correct storyboard in the saas_config".red
          return nil
        end

        puts " create new target... "
        # copy build_configurations
        new_target = @project.new_target(@main_target.symbol_type, target_name, @main_target.platform_name, @main_target.deployment_target)
        new_target.build_configurations.map do |item|
          item.build_settings.update(@main_target.build_settings(item.name))
          item.build_settings["PRODUCT_NAME"] = target_name
          item.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
          item.build_settings["INFOPLIST_FILE"] = @info_plist_path
        end
        # copy build_phases
        phases = @main_target.build_phases.reject { |x| x.instance_of? Xcodeproj::Project::Object::PBXShellScriptBuildPhase }.collect(&:class)
        phases.each do |klass|
          src = @main_target.build_phases.find { |x| x.instance_of? klass }
          dst = new_target.build_phases.find { |x| x.instance_of? klass }
          unless dst
            dst = @project.new(klass)
            new_target.build_phases << dst
          end
          dst.files.map { |x| x.remove_from_project }
          src.files.each do |f|
            build_file = @project.new(Xcodeproj::Project::Object::PBXBuildFile)
            build_file.file_ref = f.file_ref
            # libPods库让pod install 自己生成
            if dst.display_name == "Frameworks"
              dst.files << build_file unless build_file.display_name.start_with?("libPods")
              # 资源文件自己创建
            elsif dst.display_name == "Resources"
              dst.files << build_file unless build_file.display_name.end_with?("xcassets") || build_file.display_name.end_with?("storyboard")
              dst.files << build_file if build_file.display_name == "Assets.xcassets" #公共图片资源
            else
              dst.files << build_file
            end
          end
        end

        puts " create source file... "
        resources_build_phase = new_target.build_phases.find { |x| x.instance_of? Xcodeproj::Project::Object::PBXResourcesBuildPhase }
        xcassets_file = resources_build_phase.files.find { |x| x.display_name == "#{target_name}.xcassets" }
        storyboard_file = resources_build_phase.files.find { |x| x.display_name == "Launch Screen-#{target_name}.storyboard" }

        unless xcassets_file
          # copy xcassets
          puts "[ xcodeproj add xcassets_file ] ".green
          new_file_path = default_xcassets_file.file_ref.parent.real_path.to_s + "/#{target_name}.xcassets"
          FileUtils.rm_r(new_file_path) if File.directory?(new_file_path)
          FileUtils.cp_r(default_xcassets_file.file_ref.real_path.to_s + "/", new_file_path + "/")
          file_ref = default_xcassets_file.file_ref.parent.new_reference(new_file_path)
          build_file = @project.new(Xcodeproj::Project::Object::PBXBuildFile)
          build_file.file_ref = file_ref
          resources_build_phase.files << build_file

          # launch_image
          puts "[ xcodeproj add launch_image_file ] ".green
          launche_file_path = default_xcassets_file.file_ref.parent.real_path.to_s + "/LaunchImage"
          FileUtils.mkdir(launche_file_path) if !File.directory?(launche_file_path)
          launche_file_ref = default_xcassets_file.file_ref.parent.groups.find { |x| x.display_name == "LaunchImage" }
          launche_file_ref = default_xcassets_file.file_ref.parent.new_group("LaunchImage", launche_file_path) unless launche_file_ref

          new_file_path_2x = launche_file_path + "/launch_#{target_name.downcase}@2x.png"
          file_ref_2x = launche_file_ref.new_reference(new_file_path_2x)
          build_file_2x = @project.new(Xcodeproj::Project::Object::PBXBuildFile)
          build_file_2x.file_ref = file_ref_2x
          resources_build_phase.files << build_file_2x

          new_file_path_3x = launche_file_path + "/launch_#{target_name.downcase}@3x.png"
          file_ref_3x = launche_file_ref.new_reference(new_file_path_3x)
          build_file_3x = @project.new(Xcodeproj::Project::Object::PBXBuildFile)
          build_file_3x.file_ref = file_ref_3x
          resources_build_phase.files << build_file_3x
        end

        # copy storyboard
        unless storyboard_file
          puts "[ xcodeproj add storyboard_file ] ".green
          new_file_path = default_storyboard_file.file_ref.parent.real_path.to_s + "/Launch Screen-#{target_name}.storyboard"
          FileUtils.cp_r(default_storyboard_file.file_ref.real_path.to_s, new_file_path)
          file_ref = default_storyboard_file.file_ref.parent.new_reference(new_file_path)
          build_file = @project.new(Xcodeproj::Project::Object::PBXBuildFile)
          build_file.file_ref = file_ref
          resources_build_phase.files << build_file
        end

        # 修改storyboard文件中的lanuch image
        storyboard_file_path = default_storyboard_file.file_ref.parent.real_path.to_s + "/Launch Screen-#{target_name}.storyboard"
        File.open(storyboard_file_path, "r") do |file|
          xmlStoryboardfile = REXML::Document.new(file)
          if !xmlStoryboardfile.root.attributes["type"].end_with?(".XIB")
            puts "error: xmlStoryboardfile error".red
            break
          end
          # 修改image的资源名称
          xmlStoryboardfile.elements.each("document/scenes/scene/objects/viewController/view/subviews/imageView") { |e|
            if !e.attributes["image"]
              puts "error: xmlStoryboardfile image err".red
              break
            end
            e.attributes["image"] = "launch_#{target_name.downcase}.png"
            File.open(storyboard_file_path, "w") do |xml_file|
              xmlStoryboardfile.write(xml_file)
            end
          }
        end

        @project.save
        scheme = Xcodeproj::XCScheme.new
        scheme.configure_with_targets(new_target, nil, launch_target: true)
        scheme.save_as(@project.path, target_name)
        return new_target
      end

      def remove_flavor(target_name)
        puts "flavor: #{target_name} 删除中..."
        src_target = @project.targets.find { |item| item.to_s == target_name }
        resources_build_phase = src_target.build_phases.find { |x| x.instance_of? Xcodeproj::Project::Object::PBXResourcesBuildPhase }
        xcassets_file = resources_build_phase.files.find { |x| x.display_name == "#{target_name}.xcassets" }
        storyboard_file = resources_build_phase.files.find { |x| x.display_name == "Launch Screen-#{target_name}.storyboard" }
        build_file_2x = resources_build_phase.files.find { |x| x.display_name == "launch_#{target_name.downcase}@2x.png" }
        build_file_3x = resources_build_phase.files.find { |x| x.display_name == "launch_#{target_name.downcase}@3x.png" }

        if xcassets_file
          puts "[ xcodeproj remove xcassets_file ] ".green
          file_path = xcassets_file.file_ref.real_path.to_s
          FileUtils.rm_r(file_path) if File.directory?(file_path)
          xcassets_file.file_ref.remove_from_project
        end

        if build_file_2x
          puts "[ xcodeproj remove launch_image_2x ] ".green
          file_path_2x = build_file_2x.file_ref.real_path.to_s
          File.delete(file_path_2x) if File.exist?(file_path_2x)
          build_file_2x.file_ref.remove_from_project
        end

        if build_file_3x
          puts "[ xcodeproj remove launch_image_3x ] ".green
          file_path_3x = build_file_3x.file_ref.real_path.to_s
          File.delete(file_path_3x) if File.exist?(file_path_3x)
          build_file_3x.file_ref.remove_from_project
        end

        if storyboard_file
          puts "[ xcodeproj remove storyboard_file ] ".green
          file_path = storyboard_file.file_ref.real_path.to_s
          File.delete(file_path) if File.exist?(file_path)
          storyboard_file.file_ref.remove_from_project
        end

        src_target.remove_from_project
        @project.save
      end

      def config_target(flavor, target)
        target.build_configurations.each do |config|
          # config_time需要比之前大才会更新build_settings
          if flavor["config_time"] && flavor["config_time"].to_i > config.build_settings["#{@proj_name.upcase}_CONFIG_TIME"].to_i
            puts "更新build_settings: #{config.to_s}......"
            config.build_settings["#{@proj_name.upcase}_CONFIG_TIME"] = flavor["config_time"]
            config.build_settings["DISPLAY_NAME"] = flavor["app_name"]
            # 自定义业务参数配置
            extra_info = flavor["extra"]
            if extra_info && extra_info.is_a?(Hash)
              extra_info.each do |key, value|
                env_key = "#{@proj_name.upcase}_#{key.upcase}"
                @env_keys.push(env_key) unless @env_keys.include?(env_key)
                config.build_settings[env_key] = value
              end
            end
          end
        end
        @project.save
      end

      def update_images(flavor, xcassets_path)
        if xcassets_path.length <= 0
          puts "error: xcassets_path do not exist".red
          return
        end

        content_file_path = xcassets_path + "/Contents.json"
        contentsJsonStr = ""
        contentsJsonObj = {}
        contentsJsonStr = File.read(content_file_path) if File.exist?(content_file_path)
        contentsJsonObj = JSON.parse(contentsJsonStr) if contentsJsonStr.length > 0
        downloaded_images = contentsJsonObj["downloaded_images"] && contentsJsonObj["downloaded_images"].is_a?(Hash) ? contentsJsonObj["downloaded_images"] : {}

        #业务扩展图片资源
        res_extra = flavor["res_extra"]
        if res_extra && res_extra.is_a?(Hash)
          res_extra.each do |name, images|
            images.each { |key, url|
              key_string = name + key
              if url.length > 0 && downloaded_images[key_string] != url
                puts "图片下载: #{key_string}".green
                suffix_number = key[1]
                imageset_path = xcassets_path + "/#{name}.imageset"
                FileUtils.mkdir(imageset_path) if !File.directory?(imageset_path)
                image_path = imageset_path + "/#{name}@#{suffix_number}x.png"
                open(url) do |u|
                  File.open(image_path, "wb") { |f|
                    f.write(u.read)
                    downloaded_images[key_string] = url
                  }
                end
              end
            }
          end
        end

        #下载关于页面图片
        about_images = flavor["about_us_icon"]
        about_images.each { |key, url|
          key_string = "about_us_icon" + key
          if url.length > 0 && downloaded_images[key_string] != url
            puts "图片下载: #{key_string}".green
            suffix_number = key[1]
            about_imageset_path = xcassets_path + "/About.imageset"
            if File.directory?(about_imageset_path)
              image_path = about_imageset_path + "/About@#{suffix_number}x.png"
              open(url) do |u|
                File.open(image_path, "wb") { |f|
                  f.write(u.read)
                  downloaded_images[key_string] = url
                }
              end
            else
              puts "error: About.imageset do not exist, create it in #{flavor["app_merchant"]}.xcassets".red
            end
          end
        }

        #下载首页品牌logo
        home_images = flavor["home_logo"]
        home_images.each { |key, url|
          key_string = "home_logo" + key
          if url.length > 0 && downloaded_images[key_string] != url
            puts "图片下载: #{key_string}".green
            suffix_number = key[1]
            image_name = "230x50"
            image_name = "345x75" if suffix_number.to_i == 3

            home_default_logo_path = xcassets_path + "/home_default_logo.imageset"
            if File.directory?(home_default_logo_path)
              image_path = home_default_logo_path + "/#{image_name}@#{suffix_number}x.png"
              open(url) do |u|
                File.open(image_path, "wb") { |f|
                  f.write(u.read)
                  downloaded_images[key_string] = url
                }
              end
            else
              puts "error: home_default_logo.imageset do not exist, create it in #{flavor["app_merchant"]}.xcassets".red
            end
          end
        }

        #下载App icon
        appicon_images = flavor["launcher_icon"]
        appicon_sizes = ["40", "58", "60", "80", "87", "120", "180", "1024"]
        appicon_images.each { |key, url|
          key_string = "app-icon" + key
          sizeStr = key[1, key.length - 1]
          needload = appicon_sizes.include?(sizeStr)
          if url.length > 0 && downloaded_images[key_string] != url && needload
            puts "图片下载: #{key_string}".green
            appicon_appiconset_path = xcassets_path + "/AppIcon.appiconset"
            if File.directory?(appicon_appiconset_path)
              image_path = appicon_appiconset_path + "/#{sizeStr}x#{sizeStr}.png"
              open(url) do |u|
                File.open(image_path, "wb") { |f|
                  f.write(u.read)
                  downloaded_images[key_string] = url
                }
              end
            else
              puts "error: AppIcon.appiconset do not exist, create it in #{flavor["app_merchant"]}.xcassets".red
            end
          end
        }

        #下载启动图
        launch_images = flavor["splash_logo"]
        launch_images.each { |key, url|
          key_string = "splash_logo" + key
          if url.length > 0 && downloaded_images[key_string] != url
            puts "图片下载: #{key_string}".green
            suffix_number = key[1]
            image_name = "launch_#{flavor["app_merchant"].downcase}"
            parent_path = Pathname.new(xcassets_path).parent.to_s + "/LaunchImage"
            if File.directory?(parent_path)
              image_path = parent_path + "/#{image_name}@#{suffix_number}x.png"
              open(url) do |u|
                File.open(image_path, "wb") { |f|
                  f.write(u.read)
                  downloaded_images[key_string] = url
                }
              end
            else
              puts "error: LaunchImage  do not exist".red
            end
          end
        }

        contentsJsonObj["downloaded_images"] = downloaded_images
        File.write(content_file_path, JSON.dump(contentsJsonObj))
      end

      def config_plist
        # plist更新
        puts "更新info.plist......"
        info_plist = Xcodeproj::Plist.read_from_path(@info_plist_path)
        if info_plist.nil?
          puts "==============================\nError: Not found plist in path:#{@info_plist_path}!!!\n==============================\n".red
          return
        end
        @env_keys.each do |env_key|
          # info_plist key 采用驼峰命名
          plist_key = env_key.split("_").collect(&:capitalize).join("").insert(@proj_name.length, " ")
          puts plist_key
          info_plist[plist_key] = "$(#{env_key})"
        end
        # 启动图storyboard设置
        info_plist["UILaunchStoryboardName"] = "Launch Screen-$(PRODUCT_NAME)"
        Xcodeproj::Plist.write_to_path(info_plist, @info_plist_path)
      end

      def save_proj_json
        file = File.new("./pbxproj.json", "w+")
        file.puts JSON.dump(@project.pretty_print)
        file.close
      end
    end
  end
end