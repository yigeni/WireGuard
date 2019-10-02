#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================================#
#   系统要求: CentOS 7 X86_64                                     #
#   说明: WireGuard For CentOS 7 X86_64 Install                   #
#   作者: anmianyao                                               #
#   网站: https://www.yigeni.com/                                 #
#=================================================================#

clear
echo
echo "#############################################################"
echo "# WireGuard For CentOS 7 X86_64 Install                     #"
echo "# 作者: anmianyao                                           #"
echo "# 网站: https://www.yigeni.com/                             #"
echo "# 系统要求：CentOS 7 X86_64                                 #"
echo "#############################################################"
echo

# Color
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
font="\033[0m"

# 更新系统
wireguard_update(){
yum -y update
read -p "系统更新完成，需要重新启动才能继续，重启完成后请重新执行此脚本并选择2开始安装，是否现在重启？[Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "${Info} 服务器正在重启"
		reboot
	fi
}

wireguard_install(){
# ServerPort input
read -p "请输入WireGuard的服务端口号:" ServerPort

# 公网网卡名获取
read -p "请输入你的服务器公网网卡名字(一般均为eth0):" NetworkName

# 获取服务器公网IP
ServerIP=$(curl ifconfig.me)

# Disable SELinux Function
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}
# Stop SElinux
disable_selinux

# 安装EPEL源
yum -y install epel-release
if [ $? -eq 0 ];then
    echo -e "${green} EPEL源安装成功 ${font}"
else 
    echo -e "${red} EPEL源安装失败 ${font}"
    exit 1
fi

# 安装内核头文件
yum -y install kernel-headers-$(uname -r) kernel-devel-$(uname -r)
if [ $? -eq 0 ];then
    echo -e "${green} 内核头文件安装成功 ${font}"
else 
    echo -e "${red} 内核头文件安装失败 ${font}"
    exit 1
fi

# 导入WireGuard源
curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
if [ $? -eq 0 ];then
    echo -e "${green} 导入WireGuard源成功 ${font}"
else 
    echo -e "${red} 导入WireGuard源失败 ${font}"
    exit 1
fi

# 安装WireGuard
yum -y install wireguard-dkms wireguard-tools
if [ $? -eq 0 ];then
    echo -e "${green} 安装WireGuard成功 ${font}"
else 
    echo -e "${red} 安装WireGuard失败 ${font}"
    exit 1
fi

# 安装FireWalld
yum -y install firewalld
if [ $? -eq 0 ];then
    echo -e "${green} 安装FireWalld成功 ${font}"
else 
    echo -e "${red} 安装FireWalld失败 ${font}"
    exit 1
fi

# 某些奇葩机器可能自带iptables
systemctl stop iptables
systemctl disable iptables

# 开启IPv4转发
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# 创建配置文件存放目录
mkdir /etc/wireguard

# 生成服务端私钥/公钥
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

# 定义服务端公钥/私钥变量
ServerPrivatekey=$(cat /etc/wireguard/privatekey)
ServerPublickey=$(cat /etc/wireguard/publickey)

# 生成客户端私钥/公钥
wg genkey | tee /etc/wireguard/clientprivatekey | wg pubkey > /etc/wireguard/clientpublickey

# 定义客户端公钥/私钥变量
ClientPrivatekey=$(cat /etc/wireguard/clientprivatekey)
ClientPublickey=$(cat /etc/wireguard/clientpublickey)

# 创建服务端配置文件
cat > /etc/wireguard/wg0.conf << EOF

[Interface]
PrivateKey = ${ServerPrivatekey}
Address = 192.168.0.1/24
ListenPort = ${ServerPort}
DNS = 8.8.8.8

[Peer]
PublicKey = ${ClientPublickey}
AllowedIPs = 192.168.0.0/24
EOF

# 创建客户端配置文件
cat > /etc/wireguard/client.conf << EOF

[Interface]
PrivateKey = ${ClientPrivatekey}
Address = 192.168.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = ${ServerPublickey}
Endpoint = ${ServerIP}:${ServerPort}
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

# 启动防火墙
systemctl start firewalld.service
if [ $? -eq 0 ];then
    echo -e "${green} 启动防火墙成功 ${font}"
else 
    echo -e "${red} 启动防火墙失败 ${font}"
    exit 1
fi
systemctl enable firewalld.service

# 设置端口转发/放行端口
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.0.0/24 masquerade'
firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i wg0 -o ${NetworkName} -j ACCEPT
firewall-cmd --permanent --add-port=${ServerPort}/udp
firewall-cmd --reload

# 启动WireGuard
wg-quick up wg0
if [ $? -eq 0 ];then
    echo -e "${green} WireGuard启动成功 ${font}"
else 
    echo -e "${red} WireGuard启动失败 ${font}"
    exit 1
fi

# 设置开机启动
systemctl enable wg-quick@wg0

# 打印客户端配置文件
cat /etc/wireguard/client.conf

echo
echo "#############################################################"
echo "将上面的客户端信息保存到本地电脑即可连接                         "
echo
}

# 开始菜单设置
start_menu(){
	read -p "请输入数字(1或者2)，初次安装请先选择1更新系统:" num
	case "$num" in
		1)
		wireguard_update
		;;
		2)
		wireguard_install
		;;
	esac
}

# 运行开始菜单
start_menu
