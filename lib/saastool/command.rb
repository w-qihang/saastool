require "claide"
require "yaml"
require "json"

module Saas
  class Command < CLAide::Command
    require "saastool/command/init"
    require "saastool/command/update"
    require "saastool/command/mix"
    require "saastool/command/build"
    require "saastool/command/upload"

    self.abstract_command = true
    self.command = "saas"
    self.version = SaasTool::VERSION
    self.description = "Saas project managment tool"

    def self.run(argv)
      help! "You cannot run SaasTool as root." if Process.uid == 0
      super(argv)
    end

    def saas_config
      raise StandardError, "Not found saas_config.yml on current directory, exec 'saas init' first!!!" unless File.exist? "saas_config.yml"
      YAML::load(File.open("saas_config.yml"))
    end

    def merchant_hash
      raise StandardError, "Not found MerchantList.json on current directory, exec 'saas init' first!!!" unless File.exist? "MerchantList.json"
      JSON.parse(File.read("MerchantList.json"))
    end
  end
end