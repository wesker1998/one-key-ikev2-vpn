# 一键搭建 IKEv2 VPN

------
[![Author](https://img.shields.io/badge/author-%40quericy-blue.svg)](https://quericy.me)   [![Platform](https://img.shields.io/badge/Platform-Debian%2012%2B%20%7C%20RHEL%208%2B-green.svg)]()  [![GitHub stars](https://img.shields.io/github/stars/quericy/one-key-ikev2-vpn.svg)](https://github.com/quericy/one-key-ikev2-vpn/stargazers)  [![GitHub license](https://img.shields.io/badge/license-GPLv3-yellowgreen.svg)](https://raw.githubusercontent.com/quericy/one-key-ikev2-vpn/master/LICENSE)

使用bash脚本一键搭建Ikev2的vpn服务端.

特性
=============
> * 服务端：Debian 12+ 或 RHEL 8+ 兼容系统（如 Rocky Linux、AlmaLinux），需 root 权限；不支持 Ubuntu 和 Fedora
> * 客户端：支持 IKEv2 的 iOS、macOS、Windows、Linux 和 Android 等设备；实际可用的认证方式取决于客户端
> * 可使用自己的私钥和根证书，也可自动生成
> * 证书可绑定域名或ip
> * 编译安装 strongSwan 6.1.0，使用兼容的传统 ipsec.conf/stroke 配置
> * 安装时生成随机登录密码和预共享密钥
> * 客户端 IPv4 地址池为 `10.31.2.0/24`，下发 DNS 为 `8.8.8.8` 和 `8.8.4.4`

**注意**：脚本会安装编译依赖和 strongSwan，覆盖 `/usr/local/etc/ipsec.conf`、`/usr/local/etc/strongswan.conf`、`/usr/local/etc/ipsec.secrets`、`/usr/local/etc/strongswan.d/charon/kernel-libipsec.conf` 及 `/etc/sysctl.d/10-ipsec.conf`，并修改防火墙规则。iptables 模式还会覆盖 `/etc/iptables.rules`。重复运行会重新生成凭据及自签名证书，并可能重复添加防火墙规则；请事先备份现有配置和私钥。脚本不会关闭 SELinux；启用 SELinux 的系统可能需要自行配置策略。建议使用 IKEv2；脚本不提供 L2TP 服务。

历史更新
==========
> - 添加SSL证书自动申请自动更新并应用于IKEv2的解决方案,详见这篇博文:[SSL证书自动更新并应用到IKEv2, Nginx](https://quericy.me/blog/860/) ;
> - 添加对CentOS7的firewall防火墙的支持;
> - 使用ip address替换已被废弃的ifconfig;
> - 生成单独的sysctl配置文件/etc/sysctl.d/10-ipsec.conf单独加载，用于开启ipv4转发(如以后卸载或需要关闭net.ipv4.ip_forward,请记得删除此文件);
> - 升级strongswan版本到5.5.1,解决iOS9和iOS10的兼容性问题(感谢[caasiu](https://github.com/caasiu)的提醒[#21](https://github.com/quericy/one-key-ikev2-vpn/issues/21));
> - 添加导入SSL证书的支持,安装时可选使用证书颁发机构签发的证书还是生成自签名证书;

服务端安装说明
==========
1. 下载脚本:
    ```shell
    curl -fLO https://raw.githubusercontent.com/quericy/one-key-ikev2-vpn/master/one-key-ikev2.sh
    ```
    * 下载地址指向上游 master 分支，其内容可能与当前仓库不同。使用当前仓库的脚本时，请直接进入脚本所在目录。

2. 运行脚本：
    ```shell
    sudo bash one-key-ikev2.sh
    ```

    请在交互式终端中运行。脚本以**当前工作目录**存放和读取证书、源码及压缩包；以下操作均假设当前目录为脚本所在目录。

3. 脚本先安装编译依赖，并尝试获取公网 IPv4 地址作为默认值。选择 VPS 类型（Xen/KVM 或 OpenVZ），再输入服务器 IPv4 地址或域名；自动检测失败时必须手动输入。使用泛域名证书时应输入实际连接的具体域名，而不是 `*.域名`。

4. 选择导入已有证书还是生成自签名证书：

    - 选择 `no`（默认）生成自签名证书。输入 CA 证书的国家、组织和通用名称，默认分别为 `US`、`myvpn` 和 `VPN CA`；服务端证书的身份为步骤 3 输入的地址。后续会提示设置客户端 PKCS#12 证书密码，可以为空。客户端需信任生成的 CA 证书。

    - 选择 `yes` 导入已有证书。请在确认继续之前，将以下 PEM 文件放在**当前工作目录**；服务端证书必须匹配连接地址，私钥必须与证书匹配。如果证书链已受客户端信任，客户端无需额外导入 CA：
        1. **ca.cert.pem** 证书颁发机构的CA，比如Let‘s Encrypt的证书,或者其他链证书；
        2. **server.cert.pem** 签发的域名证书；
        3. **server.pem** 与服务端证书对应的私钥。

    脚本仅检查这些文件是否存在，不会验证证书链或私钥是否匹配，也不会自动续期证书；导入模式会将服务端证书和私钥同时复制为客户端证书和私钥，不会单独签发客户端证书。证书续期和应用方案可参考[这篇文章](https://quericy.me/blog/860/)。

5. 确认信息后，脚本下载并编译 strongSwan 6.1.0，生成或导入证书和随机凭据。随后可选择 SNAT，默认使用 MASQUERADE。SNAT 仅用于下面的 iptables 模式，需填写稳定的源 IPv4 地址；如果公网地址经 NAT 映射（例如 AWS 弹性 IP），应填写网络接口绑定的地址。

6. 防火墙配置：脚本启用 IPv4 转发，默认使用 iptables，也可选择已安装的 firewalld（需 systemd）。firewalld 模式使用 masquerade，不使用第 5 步的 SNAT 设置。iptables 模式默认检测 IPv4 默认路由的网卡，检测失败时 Xen/KVM 使用 `eth0`、OpenVZ 使用 `venet0`；请确认网卡名称正确。脚本会保存当前完整 iptables 规则到 `/etc/iptables.rules`，并在 systemd 系统中启用规则恢复服务。请确认不会与已有防火墙管理工具冲突，并在云平台安全组中允许 IPsec 所需流量。

    非 systemd 环境下，脚本使用 `ipsec restart` 启动服务；iptables 规则仅在 `/etc/network/if-up.d` 存在时配置自动恢复，否则需自行设置开机恢复。

7. 看到 `Install Complete` 表示安装完成。随机生成的 IKEv2 EAP 密码、IKEv1 XAUTH 密码和 PSK 会显示在终端，并保存在权限为 `600` 的 `/usr/local/etc/ipsec.secrets` 中；IKEv2 用户名默认为 `myUserName`。多用户可按现有格式添加 EAP 条目，保存并重启服务生效。请妥善保管终端输出和私钥。

8. 使用自签名证书时，将当前目录下 `my_key/ca.cert.pem` 安全地复制到客户端并导入为受信任的 CA；部分平台可能需要将后缀改为 `.cer`。`my_key` 中还包含私钥，不应整体分发。

客户端配置说明
=====
* 连接的服务器地址应与服务端证书中的身份一致，即安装时输入的 IPv4 地址或域名。

* 脚本配置了 IKEv1 PSK + XAUTH，以及证书 + XAUTH 两种连接。PSK 模式使用安装时显示的 PSK 和 XAUTH 密码；证书模式需配置客户端证书和 XAUTH 密码。是否可用取决于客户端支持，建议优先使用 IKEv2。

* 支持 IKEv2 EAP-MSCHAPv2 的客户端可使用用户名和 IKEv2 密码连接。如果服务端证书链未受信任，需要先导入并信任 CA 证书；其中：
 * **iOS/OSX** 的远程ID和服务器地址保持一致,用户鉴定选择"用户名".如果通过浏览器导入,将证书放在可访问的远程外链上,并在**系统浏览器**(Safari)中访问外链地址.OSX证书需要设置为始终信任(添加方法见**[#58](https://github.com/quericy/one-key-ikev2-vpn/issues/58)**中[JiaHaoGong](https://github.com/JiaHaoGong)的截图);
 * **Windows PC** 系统导入证书需要导入到**"本地计算机"**的"受信任的根证书颁发机构",以"当前用户"的导入方式是无效的.推荐运行mmc添加本地计算机的证书管理单元来操作;
 * **WindowsPhone8.1** 登录时的用户名可能需要带上域信息，请按客户端实际发送的用户名配置 EAP 条目。
 * **WindowsPhone10** ~~的vpn还存在bug(截至10586.164),ikeV2方式可连接但系统流量不会走vpn,只能等微软解决.~~ (截至14393.5 ,此bug已经得到修复,现在WP10已经可以正常使用IkeV2.)
 * **Windows10** 也存在此bug,部分Win10系统连接后ip不变,没有自动添加路由表,使用以下方法可解决(本方法由 bigbigfish 童鞋提供):
    * 手动关闭vpn的split tunneling功能(在远程网络上使用默认网关);
    * 也可使用powershell修改,进入CMD窗口,运行如下命令:
    ```powershell
    powershell    #进入ps控制台
    get-vpnconnection    #检查vpn连接的设置（包括vpn连接的名称）
    set-vpnconnection "vpn连接名称" -splittunneling $false    #关闭split tunneling
    get-vpnconnection   #检查修改结果
    exit   #退出ps控制台
    ```

卸载方式
===
1. 在 systemd 系统中先停止并禁用服务，再进入安装时工作目录中的 strongSwan 源码目录执行卸载：
    ```bash
    sudo systemctl disable --now strongswan-starter.service
    cd strongswan-6.1.0
    sudo make uninstall
    ```

2. 按需备份并删除安装时工作目录中的源码、`strongswan-6.1.0.tar.gz` 和 `my_key`，以及 `/usr/local/etc` 下的 IPsec 配置和证书。仅在确认不再需要时删除私钥。

3. 检查并清理脚本添加的 iptables/firewalld 规则。若使用脚本创建的 iptables 持久化服务，还需禁用 `ikev2-iptables.service`，并按需删除 `/etc/iptables.rules` 和 `/etc/systemd/system/ikev2-iptables.service`，再执行 `systemctl daemon-reload`。按需删除 `/etc/sysctl.d/10-ipsec.conf`；删除文件不会自动关闭当前已启用的 IPv4 转发，请根据其他服务的需求调整运行时设置。

分支说明
==========
* [master](https://github.com/quericy/one-key-ikev2-vpn/tree/master)分支:经过测试的相对稳定的版本;
* dev-debian分支:~~Debian6/7测试分支,该脚本由[bestoa](https://github.com/bestoa)修改提供~~.主分支已提供对Debian的支持,该分支已废弃:[#59](https://github.com/quericy/one-key-ikev2-vpn/issues/59);
* [dev](https://github.com/quericy/one-key-ikev2-vpn/tree/dev)分支:开发分支,使用最新版本的strongswan,未进过充分测试,用于尝试和添加一些新的功能,未来可能添加对L2TP的兼容支持,以及对ipv6的支持;

部分问题解决方案
======
* 在 systemd 系统上检查或重启服务：
    ```bash
    systemctl status strongswan-starter.service
    systemctl restart strongswan-starter.service
    ```

* ipsec常用指令:
    ```bash
    ipsec start   #启动服务
    ipsec stop    #关闭服务
    ipsec restart #重启服务
    ipsec reload  #重新读取
    ipsec status  #查看状态
    ipsec --help  #查看帮助
    ```

* 可连接但是无法访问网络：
    - 检查iptables是否正常启用,检查iptables规则是否与其他地方冲突,或根据服务器防火墙的实际情况手动修改配置。
    - 使用 `sysctl net.ipv4.ip_forward` 检查 IPv4 转发是否为 `1`。脚本写入 `/etc/sysctl.d/10-ipsec.conf` 并执行 `sysctl --system`；检查其他 sysctl 配置是否覆盖了该值。

* 如果之前使用的自签名证书，后改用SSL证书，部分客户端可能需要卸载之前安装的自签名证书,否则可能会报`Ike凭证不可接受`的错误:
    * iOS：设置-通用，删除证书对应的描述文件即可；
    * Windows：Win+R,运行mmc打开Microsoft管理控制台,文件->添加管理单元,添加证书管理单元(必须选计算机账户),展开受信任的根证书颁发机构,找到对应的自签名证书,右键删除即可;
    * Windows Phone:暂时没有找到可以卸载证书的方法(除非越狱),目前只能重置来解决此问题;

* 如果服务器无法连接 `https://download.strongswan.org`，可以先在其他机器下载压缩包，再上传到运行脚本的工作目录；脚本发现同名文件时会直接使用：
    ```bash
    curl -fLO https://download.strongswan.org/strongswan-6.1.0.tar.gz
    
    scp -P your-vps-port /path/to/file account@your-vps-ip:~
    ```


* * *

如有其他疑问请戳本人博客：[https://quericy.me/blog/699/](https://quericy.me/blog/699/)
