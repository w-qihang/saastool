# saastool

saastool 用来管理SaaS类应用工程配置、代码混淆、打包推送的命令行工具。

## 安装

添加源之后安装或升级

`gem install saastool`\
`gem install saastool -v 0.1.1`\
`gem update saastool`

## 命令
先执行`saas init`,后续命令依赖此命令生成文件里的一些配置参数及数据

| 命令 | 参数或子命令 | 描述 |
|-----| -----|----|
|init| 无| 生成文件MerchantList.json以及saas_config.yml|
|update|merchants|同步MerchantList.json数据至工程文件,会创建新Target.|
|build|merchants,--version=（必填）|打包命令，需指定merchants打包对应的scheme|
|upload|merchants|上传命令，需指定merchants打包对应的scheme|


## saas_config.yml配置文件
此文件会自动生成，需修正成正确配置

```
---
# xcode工程名，主target名
project: xxx
# Info.plist文件路径
info_plist_path: xxx/Info.plist
# 工程原xcassets，新生成应用时以此进行复制
main_xcassets: xxx.xcassets
# 工程原storyboard，新生成应用时以此进行复制
main_storyboard: Launch Screen-xxx.storyboard
```

## MerchantList.json数据源

此文件包含了每个应用的关键信息，可修改此文件来新增应用或编辑应用，修改完执行`saas update`


```
{
          "flavors": [
            {
              "config_time": 0, //时间戳增加才会更新Target
              "app_merchant": "XXX", //应用Target名,唯一标识
              "bundle_id": "com.saas.xxx", //应用bundle_id
              "app_name": "XXX司机端", //应用展示名称
              "pro_profile": "", //打包需要证书和描述文件，证书安装在机器上
              "itc_team_id": "", //用于上传tf包到appstore
              //启动页图片
              "splash_logo": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              //AppIcon桌面图标
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
              //关于页面图标
              "about_us_icon": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              //首页顶部logo
              "home_logo": {
                "_2x": "2x.png",
                "_3x": "3x.png",
              },
              //自定义业务扩展参数
              "extra": {
 #"key1": "value1",
                               #"key2": "value2"
                },
              //业务扩展图片
              "res_extra": {
 #"res_extra_1": {
                               #      "_2x": "2x.png",
                               #      "_3x": "3x.png"
                               #}
                },
            },
          ],
        }
```



## 打包上传
必须指定版本号\
`saas build XXX --version=1.0.0`\
`saas upload XXX XXX`

```
$ saas build --help
Usage:

    $ saas build [Merchants ...]

      使用fastlane进行打包上传

Options:

    --version                    指定要打包的版本号
    --verbose                    Show more debugging information
    --no-ansi                    Show output without ANSI codes
    --help                       Show help banner of specified command
```


## FAQ

1. json配置文件中itc_team_id如何获取：在appstoreconnect账号已登录的情况下，再访问点击https://itunesconnect.apple.com/WebObjects/iTunesConnect.woa/ra/user/detail\
如果账号已具备组织的app管理权限，则可找到与该组织对应的contentProviderId字段值，contentProviderId的值就是itc_team_id，用于fastlane上传

2. fastlane打包:\
证书、描述文件必须安装在打包机器才能成功打包\
为避免上传appstore时要求输入账号密码被中断、以及苹果双重认证的中断，可使用以下方案：\
~/.bash_profile里配置环境变量：\
export FASTLANE_USER=xxx\
export FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=xxx\
export FASTLANE_SESSION=xxx\
export ITMSTRANSPORTER_FORCE_ITMS_PACKAGE_UPLOAD=true\
配置完执行source ~/.bash_profile来生效，可能要重启生效\
FASTLANE_USER就是苹果账号用户名\
FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD需要到苹果账号管理中心进行生成：https://appleid.apple.com/ \
FASTLANE_SESSION通过执行命令`fastlane spaceauth`来生成，真正的实体要从第一个value处开始到第一个value结束，不要全部一股脑全部配置到环境变量文件中\
FASTLANE_SESSION、FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD好像有效期一个月左右，有问题更新即可